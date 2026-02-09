//// [COMBO] {"material":"ui_editor_properties_mode","combo":"MODE","type":"options","default":0,"options":{"Vertex":1,"UV":0}}

#include "common.h"

//uniform vec2 g_Offset; // {"default":"0 0","label":"ui_editor_properties_offset","material":"offset"}
//uniform vec2 g_Scale; // {"default":"1 1","label":"ui_editor_properties_scale","material":"scale"}
//uniform vec2 g_Scale; // {"default":"1 1","label":"ui_editor_properties_scale","linked":true,"material":"scale","range":[0.10000000000000001,10.0]}
//uniform float g_Direction; // {"material":"angle","label":"ui_editor_properties_angle","default":0,"range":[0,6.28],"direction":true}

uniform mat4 g_ModelViewProjectionMatrix;
uniform mat4 g_ModelViewProjectionMatrixInverse;

attribute vec3 a_Position;
attribute vec2 a_TexCoord;

varying vec4 v_TexCoord;

uniform vec2 g_PointerPosition;
uniform vec4 g_Texture0Resolution;
uniform vec4 g_Texture1Resolution;
varying vec4 v_PointerUV;

// vec2 applyFx(vec2 v) {
// 	v = rotateVec2(v - CAST2(0.5), -g_Direction);
// 	//return (v + g_Offset) * g_Scale + CAST2(0.5);
// 	return v * g_Scale + CAST2(0.5);
// }


void main() {

vec3 position = a_Position;
// #if MODE == 1
// 	position.xy = applyFx(position.xy);
// #endif
	gl_Position = mul(vec4(position, 1.0), g_ModelViewProjectionMatrix);
	
	v_TexCoord.xy = a_TexCoord;
	
// #if MODE == 0
// 	v_TexCoord.xy = applyFx(v_TexCoord);
// #endif


vec2 pointer = g_PointerPosition;
	pointer.y = 1.0 - pointer.y; // Flip pointer screen space Y to match texture space Y
	v_PointerUV.xyz = mul(vec4(pointer * 2 - 1, 0.0, 1.0), g_ModelViewProjectionMatrixInverse).xyw;
	v_PointerUV.xy *= 0.5 / g_Texture0Resolution.xy;
	v_PointerUV.w = g_Texture0Resolution.y / -g_Texture0Resolution.x;
}




