% mx, my              -> posição atual do Mario (filtrada pelo Kalman)
% sprite_atual_mario  -> índice/estado do sprite detectado do Mario
% mapa                -> estrutura contendo plataformas, escadas e demais
% bx, by              -> posição atual de cada barril rastreado(vetores, um elemento por barril)
% bvx, bvy            -> velocidade estimada de cada barril (px/frame)
% bpx, bpy            -> trajetória prevista dos barris cell arrays onde: bpx{i}(t) = posição X futura | bpy{i}(t) = posição Y futura
% fx, fy              -> posição atual do foguinho
% saidas:
% inputs              -> vetor de entrada do NES:[A B Select Start Up Down Left Right]
% Fx, Fy              -> alvo/objetivo atual escolhido

% sobre sprite_atual_mario se for:
% 1 : rosto pra a direita
% 2 : rosto para a esquerda
% 3 : subindo escada
% 4 : terminou de subir a escada (de costas)
function [inputs, Fx, Fy] = controlador_mario(mx, my, sprite_atual_mario, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy);

end
