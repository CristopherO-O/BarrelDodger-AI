clear all;
close all force;
clc;
clear controlador_mario;
#warning off;

% graphics_toolkit("fltk");

pkg load image;
pkg load retro_games;
% =====================================================
% variaveis de debug
loop_enter = true; %se vai entrar no loop.                                      padrão(true)
pc_view = true; %modo para ver como o pc está vizualizando os objetos.          padrão(false)
auto_reset = true; %se vai reiniciar automaticamente quando o mario morrer.     padrão(true)
liga_IA = false; %se a ia tá ligada ou nao
correlacao_estimada = 0.5128; %nao colocar valor menor que 0.5128(gambiarra) Vivo(de lado):0.9 ~ 1.00 Morto: 0.42 ~ 0.5128
horizonte_barril = 30; % Horizonte de previsão dos barris

% =====================================================
% inicia jogo no momento ideal e salva esse momento

[jogo, startpoint] = inicializar_emulador("DK.nes");
% Cria a janela do jogo com um controle de estado para para o loop
fig = figure('Name', 'Donkey Kong');
set(fig, 'UserData', true);
% Só fecha se a tecla pressionada for 'escape'
set(fig, 'KeyPressFcn', @(obj, event) strcmp(event.Key, 'escape') && set(obj, 'UserData', false));
% =====================================================

%inicialização

%checa se os arquivos existem e os carrega ou cria
if exist('mapa_dk_level1.mat', 'file') && exist('mc_template.mat', 'file') && exist('inimigos_template.mat', 'file')
    load('mapa_dk_level1.mat');
    load('mc_template.mat');
    load('inimigos_template.mat');
else
    [mapa, mc, inimigos] = varreduraInicial(jogo);
    jogo.set_state(startpoint);
end


if loop_enter == false

else
    % =====================================================
    % trecho para preparar para começar o jogo
    % =====================================================
    % config grafica
    figure(fig);
    img_inicial = jogo.get_image();
    MAX_SLOTS_VIS = 6; % Movido para cá

    if pc_view
        % Chama a função que cria a tela e já devolve a struct de graficos pronta
        graficos = inicializar_graficos_pc(img_inicial, mapa, MAX_SLOTS_VIS);
    else
        img_plot = imshow(img_inicial);
    end

    % =====================================================
    % configurações antes do loop
    frames_sem_mario = 0;
    limite_sumido    = 10;

    ultimo_mx = NaN;
    ultimo_my = NaN;

    % Maquina de estados do Mario (ANDANDO / PULANDO / NA_ESCADA)
    estado_mario = EstadoMario();

    kelman(0, 0, 0, true);
    jogo.set_input([0 0 0 0 0 1 0 0]);
    % =====================================================
    % LOOP PRINCIPAL
    % =====================================================

    while ishandle(fig) && get(fig, 'UserData') == true
        % ===== tick =====
        jogo.step(2);
        imc = jogo.get_image();
        img = rgb2gray(imc);

        % Localiza Mario
        [mx_bruto, my_bruto, sprite_atual_mario, mscr] = localizar_mario(img, mc);

        % Rastreia barris com Kalman
        [bx, by, bvx, bvy, bpx, bpy, bfx, bfy, barris_id] = rastreia_barril(img, inimigos.barril, horizonte_barril, mapa);

        % Localiza foguinho
        [fx, fy] = localizar_foguinho(img);

        % Filtra posição do Mario
        [mx, my] = kelman(mx_bruto, my_bruto, mscr, false);

        if mscr > correlacao_estimada
            frames_sem_mario = 0;
            % Atualiza a maquina de estados so quando o Mario foi
            % localizado com confianca (senao a leitura de x/y/sprite
            % seria lixo e contaminaria a deteccao de estado).
            estado_mario.atualizar(mx, my, sprite_atual_mario, mscr);
        else
            frames_sem_mario = frames_sem_mario + 1;
        end

        % ===== CONTROLE DE MORTE / RESET =====
        if auto_reset && frames_sem_mario >= limite_sumido
            disp('Mario sumiu/morreu! Resetando para o ponto inicial...');
            jogo.set_state(startpoint);
            frames_sem_mario = 0;

            kelman(0, 0, 0, true);
            clear controlador_mario;
            estado_mario.reiniciar();

            % Reseta também os trackers dos barris (limpa estado persistente)
            clear rastreia_barril;

            if pc_view
                set(graficos.mario_plot, 'XData', NaN, 'YData', NaN);
                for s = 1:MAX_SLOTS_VIS
                    set(graficos.prev_plots(s), 'XData', NaN, 'YData', NaN);
                    set(graficos.fant_plots(s), 'XData', NaN, 'YData', NaN);
                end
                set(graficos.impacto_plot, 'XData', NaN, 'YData', NaN);
            end
            continue;
        end
        Fx = 0; Fy = 0;
        if liga_IA
            [inputs_ia, Fx, Fy] = controlador_mario(mx, my, sprite_atual_mario, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy);
            jogo.set_input(inputs_ia);
        end

        % ===== render =====
        if pc_view
            atualizar_pc_view(graficos, imc, frames_sem_mario, limite_sumido, mx, my, bx, by, barris_id, bpx, bpy, bfx, bfy, fx, fy, estado_mario.EstadoAtual, MAX_SLOTS_VIS);
        else
            set(img_plot, 'CData', img);
            drawnow;
        end
        pause(0.01);

    end
end

pause(0.2);

if ishandle(fig)
    close(fig);
end
drawnow;

disp('processo encerrado.');