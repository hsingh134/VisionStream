#!/usr/bin/env python3
"""Reproducible geometry-only reference; no display or perceptual measurements."""
import json, math, time

def measure(columns, rows):
    vertices=[]
    for y in range(rows+1):
        latitude=(.5-y/rows)*math.pi
        for x in range(columns+1):
            longitude=(x/columns-.5)*math.pi
            vertices.append(((math.sin(longitude)*math.cos(latitude),math.sin(latitude),-math.cos(longitude)*math.cos(latitude)),(x/columns,1-y/rows)))
    errors=[];started=time.monotonic()
    weights=[(1/3,1/3,1/3),(.6,.2,.2),(.2,.6,.2),(.2,.2,.6)]
    for y in range(rows):
        for x in range(columns):
            a=y*(columns+1)+x;b=a+columns+1
            for triangle in [(a,b,a+1),(a+1,b,b+1)]:
                for weight in weights:
                    p=[sum(vertices[i][0][c]*w for i,w in zip(triangle,weight)) for c in range(3)]
                    uv=[sum(vertices[i][1][c]*w for i,w in zip(triangle,weight)) for c in range(2)]
                    latitude=math.asin(max(-1,min(1,p[1]/math.sqrt(sum(c*c for c in p)))))
                    if abs(latitude)>math.radians(75):continue
                    exact=(math.atan2(p[0],-p[2])/math.pi+.5,latitude/math.pi+.5)
                    errors.append(math.hypot(exact[0]-uv[0],exact[1]-uv[1])*4096)
    errors.sort()
    return dict(columns=columns,rows=rows,samples=len(errors),eyeWidth=4096,eyeHeight=4096,latitudeLimit=75,
                maxTexelError=max(errors),p95TexelError=errors[int(.95*(len(errors)-1))],seconds=time.monotonic()-started)

if __name__=='__main__':
    print(json.dumps(dict(scope='Geometry-only equirectangular UV interpolation; four barycentric samples per triangle; not rendered display pixels',
        meshes=[measure(c,r) for c,r in [(128,64),(256,128),(512,256)]],
        disparityExample=dict(syntheticIPDMetres=.064,eyeWidth=4096,horizontalDegrees=180,
            offsetTexelsAt10m=2*math.atan(.064/(2*10))/math.pi*4096,
            offsetTexelsAt1000m=2*math.atan(.064/(2*1000))/math.pi*4096)),indent=2))
