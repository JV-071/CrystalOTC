uniform float u_Time;
uniform sampler2D u_Tex0;
uniform vec2 u_Resolution;

varying vec2 v_TexCoord;

void main() {
    vec4 pixel = texture2D(u_Tex0, v_TexCoord);

    // Tempo total de sobreposição (em segundos)
    float totalOverlayTime = 5.0;  // Ajuste conforme necessário

    // Calcula a fração do tempo total de sobreposição
    float overlayFraction = min(u_Time / totalOverlayTime, 1.0);

    // Cor de preenchimento azul
    vec4 fill_colour = vec4(0.0, 0.5, 1.0, 0.35);

    // Mescla gradualmente a cor azul com a cor existente do pixel
    pixel.rgb = mix(pixel.rgb, fill_colour.rgb, overlayFraction * fill_colour.a);

    gl_FragColor = pixel;
}