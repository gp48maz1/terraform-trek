/* shaders/arrow_pulse.frag */
#ifdef GL_ES
#define PRECISION mediump
precision PRECISION float;
#else
#define PRECISION
#endif

// Passed from vertex shader:
varying vec4 v_color;
varying vec2 v_texcoord;

// LÖVE uniforms (we still need love_texture for Texel)
uniform sampler2D love_texture;

// Output color function (provided by LÖVE):
#define love_PixelColor_out vec4
#ifdef GL_ES
#define Texel(c) texture2D(love_texture, v_texcoord) * vec4(c.rgb * v_color.rgb, c.a * v_color.a)
#else
#define Texel(c) texture(love_texture, v_texcoord) * vec4(c.rgb * v_color.rgb, c.a * v_color.a)
#endif
vec4 love_PixelColor(void);

void main() {
    // Simplest possible: just pass through the vertex color modulated by texture (usually white for lines)
    love_PixelColor_out = Texel(vec4(1.0));
} 