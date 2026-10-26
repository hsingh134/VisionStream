#include "MediaRemux.h"
#include <stdlib.h>
#include <stdatomic.h>
#include <errno.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/log.h>
#include <libavcodec/packet.h>
struct VSMediaContext { atomic_int cancelled; };
VSMediaContext *vs_media_create(void) {
    VSMediaContext *c=calloc(1,sizeof(*c));if(c)atomic_init(&c->cancelled,0);return c;
}
void vs_media_cancel(VSMediaContext *c) { if(c)atomic_store(&c->cancelled,1); }
void vs_media_destroy(VSMediaContext *c) { free(c); }
static int interrupted(void *opaque) { return atomic_load(&((VSMediaContext *)opaque)->cancelled); }
const char *vs_media_license(void) { return avformat_license(); }
const char *vs_media_version(void) { return av_version_info(); }
int32_t vs_media_remux(VSMediaContext *c,const char *input,const char *output,int64_t maximum) {
    if(!c||!input||!output||maximum<=0)return AVERROR(EINVAL);
    // Local files only: this build has no network protocols. Do not let library
    // diagnostic strings, filenames or malformed-container text reach logs.
    av_log_set_level(AV_LOG_QUIET);
    AVFormatContext *in=avformat_alloc_context(),*out=NULL;
    AVPacket *packet=NULL;AVDictionary *options=NULL;
    int result=AVERROR(ENOMEM),map[16],video=0,audio=0;
    if(!in)goto done;
    in->interrupt_callback=(AVIOInterruptCB){interrupted,c};
    in->probesize=8*1024*1024;in->max_analyze_duration=5*AV_TIME_BASE;
    result=avformat_open_input(&in,input,NULL,NULL);if(result<0)goto done;
    result=avformat_find_stream_info(in,NULL);if(result<0)goto done;
    if(in->nb_streams>16){result=AVERROR(EINVAL);goto done;}
    result=avformat_alloc_output_context2(&out,NULL,"mp4",output);if(result<0)goto done;if(!out){result=AVERROR(ENOMEM);goto done;}
    for(unsigned i=0;i<in->nb_streams;i++) {
        AVCodecParameters *p=in->streams[i]->codecpar;map[i]=-1;
        if(p->codec_type!=AVMEDIA_TYPE_AUDIO&&p->codec_type!=AVMEDIA_TYPE_VIDEO)continue;
        if(p->codec_type==AVMEDIA_TYPE_VIDEO) {
            if(++video>1||(p->codec_id!=AV_CODEC_ID_H264&&p->codec_id!=AV_CODEC_ID_HEVC)||p->width<=0||p->height<=0||p->width>8192||p->height>8192){result=AVERROR(EINVAL);goto done;}
        } else if(++audio>1||p->codec_id!=AV_CODEC_ID_AAC){result=AVERROR(EINVAL);goto done;}
        AVStream *stream=avformat_new_stream(out,NULL);if(!stream){result=AVERROR(ENOMEM);goto done;}
        map[i]=stream->index;
        result=avcodec_parameters_copy(stream->codecpar,p);if(result<0)goto done;
        stream->codecpar->codec_tag=0;stream->time_base=in->streams[i]->time_base;
    }
    if(video!=1||audio!=1){result=AVERROR(EINVAL);goto done;}
    out->interrupt_callback=(AVIOInterruptCB){interrupted,c};
    result=avio_open2(&out->pb,output,AVIO_FLAG_WRITE,&out->interrupt_callback,NULL);if(result<0)goto done;
    av_dict_set(&options,"movflags","+faststart",0);
    result=avformat_write_header(out,&options);av_dict_free(&options);if(result<0)goto done;
    packet=av_packet_alloc();if(!packet){result=AVERROR(ENOMEM);goto done;}
    while(!interrupted(c)) {
        result=av_read_frame(in,packet);
        if(result==AVERROR_EOF){result=0;break;}
        if(result<0)goto done;
        int index=packet->stream_index;
        if(index<0||index>=(int)in->nb_streams||packet->size<0||packet->size>64*1024*1024){result=AVERROR(EINVAL);goto done;}
        if(map[index]<0){av_packet_unref(packet);continue;}
        AVStream *source=in->streams[index],*destination=out->streams[map[index]];
        if(in->start_time!=AV_NOPTS_VALUE) {
            int64_t offset=av_rescale_q(in->start_time,AV_TIME_BASE_Q,source->time_base);
            if(packet->pts!=AV_NOPTS_VALUE)packet->pts-=offset;
            if(packet->dts!=AV_NOPTS_VALUE)packet->dts-=offset;
        }
        av_packet_rescale_ts(packet,source->time_base,destination->time_base);
        packet->stream_index=destination->index;packet->pos=-1;
        result=av_interleaved_write_frame(out,packet);av_packet_unref(packet);if(result<0)goto done;
        if(avio_tell(out->pb)>maximum){result=AVERROR(ENOSPC);goto done;}
    }
    if(interrupted(c)){result=AVERROR_EXIT;goto done;}
    result=av_write_trailer(out);
    if(avio_tell(out->pb)>maximum)result=AVERROR(ENOSPC);
done:
    av_dict_free(&options);av_packet_free(&packet);
    if(in)avformat_close_input(&in);
    if(out){if(out->pb){int closed=avio_closep(&out->pb);if(result>=0&&closed<0)result=closed;}avformat_free_context(out);}
    return result;
}
