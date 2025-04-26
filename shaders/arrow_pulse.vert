/* shaders/arrow_pulse.vert */
#ifdef GL_ES
#define PRECISION mediump
#else
#define PRECISION
#endif

// Passed from LÖVE:
attribute vec4 love_Vertex;
attribute vec4 love_Color; // We won't use this directly, using uniform instead
attribute vec2 love_TexCoord; // We won't use this

uniform mat4 love_ModelViewProjectionMatrix;

// Passed to fragment shader:
varying vec4 v_color;
varying vec2 v_texcoord;

void main() {
    v_color = love_Color;
    v_texcoord = love_TexCoord;
    gl_Position = love_ModelViewProjectionMatrix * love_Vertex;
} 