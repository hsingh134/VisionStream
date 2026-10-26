#ifndef VISIONSTREAM_MEDIA_REMUX_H
#define VISIONSTREAM_MEDIA_REMUX_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct VSMediaContext VSMediaContext;
VSMediaContext *vs_media_create(void);
void vs_media_cancel(VSMediaContext *context);
void vs_media_destroy(VSMediaContext *context);
int32_t vs_media_remux(VSMediaContext *context,const char *input,const char *output,int64_t maximum_output_bytes);
const char *vs_media_license(void);
const char *vs_media_version(void);
#ifdef __cplusplus
}
#endif
#endif
