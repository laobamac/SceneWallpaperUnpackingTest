// [COMBO] {"material":"ui_editor_properties_blend_mode","combo":"BLENDMODE","type":"imageblending","default":31}
//// [COMBO] {"material":"ui_editor_properties_repeat","combo":"CLAMP","type":"options","default":1}
// [COMBO] {"material":"Sun options","combo":"SUN","type":"options","default":0,"options":{"Disabled":1,"Sun":0}}
// [COMBO] {"material":"Lens flare options","combo":"LENS","type":"options","default":0,"options":{"Disabled":1,"Lens flare":0}}


uniform sampler2D g_Texture0; // {"material":"framebuffer","label":"ui_editor_properties_framebuffer","hidden":true}
uniform sampler2D g_Texture1; // {"default":"util/noise","hidden":false,"material":"noise"}
uniform vec3 u_color1; // {"default":"1 1 1","material":"Color","type":"color"}
uniform float u_DistOpacity; // {"default":"1","material":"Opacity"}
uniform float u_Speed; // {"material":"speed","label":"Speed","default":0.25,"range":[-1,1]}
uniform float u_Speed1; // {"material":"speed secondary","label":"Speed Secondary","default":0.125,"range":[-1,1]}
uniform float u_SpeedRot; // {"material":"rotationspeed","label":"Rotation Speed","default":1,"range":[-1,1]}
uniform float g_Time;
uniform float u_Scale; // {"material":"Scale","default":0.025,"range":[0,1]}
uniform float u_SunScale; // {"material":"Sun Scale","default":32,"range":[0,1024]}

uniform vec2 u_OffSet; // {"default":"-2 -0.5","material":"Position offset"}

uniform vec4 g_Texture1Resolution;

varying vec4 v_TexCoord;
uniform vec4 g_Texture0Resolution;

uniform float u_pointerSpeed; // {"material":"pointerspeed","label":"Cursor Influence","default":1,"range":[-1,1]}
uniform vec2 g_PointerPosition;
varying vec4 v_PointerUV;
varying vec4 timer;
varying vec4 timer2;
varying vec2 rotation;
varying vec2 rotation2;

uniform float g_Direction; // {"material":"angle","label":"ui_editor_properties_angle","default":0,"range":[0,6.28],"direction":true}


#include "common.h"
#include "common_blending.h"
#define M_PI_F 3.14159265358979323846f



float noise(float t)
{
	return texSample2D(g_Texture1,vec2(t,.0)/g_Texture1Resolution.xy).x;
}
float noise(vec2 t)
{
	return texSample2D(g_Texture1,t/g_Texture1Resolution.xy).x;
}

vec3 lensflare(vec2 uv,vec2 pos)
{
	uv += u_OffSet + rotateVec2(pos - CAST2(0.5), -g_Direction);
	vec2 main = uv-pos;
	vec2 uvd = uv*(length(uv));
	
	float ang = atan2(main.x,main.y);
	float dist=length(main); dist = pow(dist,.1);
	float n = noise(vec2(ang*16.0,dist*32.0));
	
	float f0 = 1.0/(length(uv-pos)*u_SunScale+1.0);
	
	f0 = f0 + f0*(sin(noise(sin(ang*2.+pos.x)*4.0 - cos(ang*3.+pos.y))*16.)*.1 + dist*.1 + .8);
	
	float f1 = max(0.01-pow(length(uv+1.2*pos),1.9),.0)*7.0;

	float f2 = max(1.0/(1.0+32.0*pow(length(uvd+0.8*pos),2.0)),.0)*00.25;
	float f22 = max(1.0/(1.0+32.0*pow(length(uvd+0.85*pos),2.0)),.0)*00.23;
	float f23 = max(1.0/(1.0+32.0*pow(length(uvd+0.9*pos),2.0)),.0)*00.21;
	
	vec2 uvx = mix(uv,uvd,-0.5);
	
	float f4 = max(0.01-pow(length(uvx+0.4*pos),2.4),.0)*6.0;
	float f42 = max(0.01-pow(length(uvx+0.45*pos),2.4),.0)*5.0;
	float f43 = max(0.01-pow(length(uvx+0.5*pos),2.4),.0)*3.0;
	
	uvx = mix(uv,uvd,-.4);
	
	float f5 = max(0.01-pow(length(uvx+0.2*pos),5.5),.0)*2.0;
	float f52 = max(0.01-pow(length(uvx+0.4*pos),5.5),.0)*2.0;
	float f53 = max(0.01-pow(length(uvx+0.6*pos),5.5),.0)*2.0;
	
	uvx = mix(uv,uvd,-0.5);
	
	float f6 = max(0.01-pow(length(uvx-0.3*pos),1.6),.0)*6.0;
	float f62 = max(0.01-pow(length(uvx-0.325*pos),1.6),.0)*3.0;
	float f63 = max(0.01-pow(length(uvx-0.35*pos),1.6),.0)*5.0;
	
	vec3 c = vec3(0,0,0);
#if LENS == 0	
	c.r+=f2+f4+f5+f6; c.g+=f22+f42+f52+f62; c.b+=f23+f43+f53+f63;
#endif

#if LENS == 1
#endif
	//c = c*1.3 - vec3(length(uvd)*0.5,0.5,0.5); //black background
#if SUN == 0	
	c+= vec3(0,0,0) + f0 /1;//sun
#endif

#if SUN == 1
	c+= vec3(0,0,0) + f0 /100;//sun
#endif
	return c;	
}


vec3 cc(vec3 color, float factor,float factor2) // color modifier
{
	float w = color.x+color.y+color.z;
	return mix(color,vec3(w,0,0)*factor,w*factor2);
}

void main()
{
	float timer = sin(g_Time * u_Speed);
	vec2 rotation = rotateVec2(CAST2(0.5), - u_SpeedRot * g_Time);
	float timer2 = cos(g_Time * u_Speed1);
	float pointer = g_PointerPosition.xy * u_pointerSpeed;
	vec4 scene = texSample2D(g_Texture0, v_TexCoord.xy);
	vec2 uv = v_TexCoord.xy / g_Texture0Resolution.y / u_Scale *100 -0.5;
	uv.x *= g_Texture0Resolution.x/g_Texture0Resolution.y; //fix aspect ratio
	vec3 color = vec3(1.4,1.2,1.0)*u_color1*lensflare(uv, rotation + timer * timer2 + (u_pointerSpeed * g_PointerPosition.xy + pointer));
	color -= noise(v_TexCoord.xy)*.015;
	color = cc(color,.5,.1);
	
vec3 finalColor = color;

	// Apply blend mode
	finalColor = ApplyBlending(BLENDMODE, lerp(finalColor.rgb, scene.rgb, scene.a), finalColor.rgb, u_DistOpacity);

float alpha = scene.a;

	gl_FragColor = vec4(finalColor,alpha);
}

