clear variables;
close all force;
clc;
clear controlador_mario;
#warning off;

graphics_toolkit("fltk");

pkg load image;
pkg load retro_games;
% =====================================================
% variaveis de debug/config
loop_enter = true; %se vai entrar no loop principal.                                      padrão(true)
pc_view = true; %modo para ver como o pc está vizualizando os objetos.          padrão(false)
auto_reset = true; %se vai reiniciar automaticamente quando o mario morrer.     padrão(true)
modo_ia = 'nqlearn'; %qual IA controla o Mario: 'controlador', 'nqlearn', 'qlearn' ou 'desligado'.
% =====================================================
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

    if pc_view
        % tela do jogo
        subplot(1, 2, 1);
        img_plot_pc = imshow(img_inicial);
        title('Visão Normal');

        % Visão do Computador
        subplot(1, 2, 2);
        imshow(mapa.plataformas);
        title('PC View — Kalman');
        hold on;

        % Desenha as escadas uma única vez
        for i = 1:length(mapa.escadas_lista)
            x_escada = mapa.escadas_lista(i).x_centro;
            y_topo   = mapa.escadas_lista(i).y_topo;
            y_base   = mapa.escadas_lista(i).y_base;
            plot([x_escada, x_escada], [y_topo, y_base], 'g-', 'LineWidth', 2);
            y_meio = (y_topo + y_base) / 2;
            text(x_escada + 4, y_meio, num2str(i), 'Color', 'y', 'FontSize', 10, 'FontWeight', 'bold');
        end

        % Mario
        mario_plot = plot(NaN, NaN, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 8);

        % Barris — posição atual
        barris_plot = plot(NaN, NaN, 'o', ...
            'MarkerEdgeColor', [1 0.5 0], 'MarkerFaceColor', [1 0.5 0], 'MarkerSize', 7);

        % Trajetória prevista dos barris
        MAX_SLOTS_VIS = 6;
        
        prev_plots = zeros(MAX_SLOTS_VIS, 1); 
        
        for s = 1:MAX_SLOTS_VIS
            prev_plots(s) = plot(NaN, NaN, '--', 'Color', [1 0.65 0], 'LineWidth', 1.2);
        end

        % Ponto de impacto previsto 
        impacto_plot = plot(NaN, NaN, 'x', ...
            'Color', [1 0.2 0.2], 'MarkerSize', 10, 'LineWidth', 2);

        % Foguinho
        foguinho_plot = plot(NaN, NaN, 'o', ...
            'MarkerEdgeColor', 'y', 'MarkerFaceColor', 'y', 'MarkerSize', 6);

        hold off;
    else
        img_plot = imshow(img_inicial);
    end
    % =====================================================
    % configurações antes do loop
    frames_sem_mario = 0;
    limite_sumido    = 10;

    ultimo_mx = NaN;
    ultimo_my = NaN;

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
        [bx, by, bvx, bvy, bpx, bpy] = rastreia_barril(img, inimigos.barril, horizonte_barril);

        % Localiza foguinho
        [fx, fy] = localizar_foguinho(img);

        % Filtra posição do Mario
        [mx, my] = kelman(mx_bruto, my_bruto, mscr, false);

        if mscr > correlacao_estimada
            frames_sem_mario = 0;
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
            clear rastreia_barril;

            if strcmp(modo_ia, 'qlearn')
                Qlearn(-1, 0, 0, mapa, [], [], [], [], [], [], [], []);
            end

            if strcmp(modo_ia, 'nqlearn')
                NQlearn(-1, 0, 0, mapa, [], [], [], [], [], [], [], []);
            end

            if pc_view
                set(mario_plot, 'XData', NaN, 'YData', NaN);
                for s = 1:MAX_SLOTS_VIS
                    set(prev_plots(s), 'XData', NaN, 'YData', NaN);
                end
                set(impacto_plot, 'XData', NaN, 'YData', NaN);
            end
            continue;
        end

        Fx = 0; Fy = 0;
        switch modo_ia
            case 'controlador'
                [inputs_ia, Fx, Fy] = controlador_mario(mx, my, sprite_atual_mario, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy);
                jogo.set_input(inputs_ia);
            case 'qlearn'
                [inputs_ia, Fx, Fy] = Qlearn(mx, my, sprite_atual_mario, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy);
                jogo.set_input(inputs_ia);
            case 'nqlearn'
                [inputs_ia, Fx, Fy] = NQlearn(mx, my, sprite_atual_mario, mapa, bx, by, bvx, bvy, bpx, bpy, fx, fy);
                jogo.set_input(inputs_ia);    
            case 'desligado'
                % ninguem manda input, so fica observando (util pra debugar a visao)
            otherwise
                error('modo_ia invalido: use ''controlador'', ''qlearn'', ''nqlearn'' ou ''desligado''.');
        end

        % =====================================================
        % CONTROLE DE VITÓRIA / NOVA RUN (NOVO)
        % =====================================================
        if my < 30
            disp('🏆 MAIN LOOP: Topo alcançado! Resetando o emulador para nova run...');
            jogo.set_state(startpoint); % Volta o jogo pro começo
            frames_sem_mario = 0;

            kelman(0, 0, 0, true); % Reseta o filtro de posição
            clear controlador_mario;
            clear rastreia_barril;

            if strcmp(modo_ia, 'qlearn')
                Qlearn(-1, 0, 0, mapa, [], [], [], [], [], [], [], []);
            end
            if strcmp(modo_ia, 'nqlearn')
                NQlearn(-1, 0, 0, mapa, [], [], [], [], [], [], [], []);
            end

            % Limpa os gráficos da visão do PC
            if pc_view
                set(mario_plot, 'XData', NaN, 'YData', NaN);
                for s = 1:MAX_SLOTS_VIS
                    set(prev_plots(s), 'XData', NaN, 'YData', NaN);
                end
                set(impacto_plot, 'XData', NaN, 'YData', NaN);
            end
            
            % Pula o render desse frame e recomeça o loop direto do início
            continue; 
        end



        % ===== render =====
        if pc_view
            set(img_plot_pc, 'CData', imc);

            % Mario
            if frames_sem_mario < limite_sumido
                set(mario_plot, 'XData', mx, 'YData', my);
            else
                set(mario_plot, 'XData', NaN, 'YData', NaN);
            end

            % Barris — posição atual
            if ~isempty(bx)
                set(barris_plot, 'XData', bx, 'YData', by);
            else
                set(barris_plot, 'XData', NaN, 'YData', NaN);
            end

            % Trajetórias previstas (uma linha por barril detectado)
            imp_x_all = [];
            imp_y_all = [];
            for s = 1:MAX_SLOTS_VIS
                if s <= length(bpx) && ~isempty(bpx{s})
                    set(prev_plots(s), 'XData', bpx{s}, 'YData', bpy{s});
                    % ponto de impacto = último ponto da trajetória
                    imp_x_all(end+1) = bpx{s}(end);
                    imp_y_all(end+1) = bpy{s}(end);
                else
                    set(prev_plots(s), 'XData', NaN, 'YData', NaN);
                end
            end
            if ~isempty(imp_x_all)
                set(impacto_plot, 'XData', imp_x_all, 'YData', imp_y_all);
            else
                set(impacto_plot, 'XData', NaN, 'YData', NaN);
            end

            % Foguinho
            if ~isempty(fx)
                set(foguinho_plot, 'XData', fx, 'YData', fy);
            else
                set(foguinho_plot, 'XData', NaN, 'YData', NaN);
            end

            drawnow;
        else
            set(img_plot, 'CData', img);
            drawnow;
        end
        pause(0.01);

    end
end

disp('Limpando a memória...');
pause(0.2);

if ishandle(fig)
    close(fig);
end
drawnow;

disp('processo encerrado.');