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
    % Inicializacao da visualizacao
    % =====================================================
    figure(fig);
    img_inicial = jogo.get_image();

    view = PCView('init', fig, img_inicial, mapa, pc_view);
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
        [bx, by, bvx, bvy, bpx, bpy, bfx, bfy, bid] = rastreia_barril(img, inimigos.barril, horizonte_barril, mapa);

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

            
            % Pula o render desse frame e recomeça o loop direto do início
            continue; 
        end

        % ===== render =====
        dados_view = struct( ...
            'imc', imc, ...
            'img', img, ...
            'mx', mx, ...
            'my', my, ...
            'frames_sem_mario', frames_sem_mario, ...
            'limite_sumido', limite_sumido, ...
            'bx', bx, ...
            'by', by, ...
            'bpx', {bpx}, ...
            'bpy', {bpy}, ...
            'bfx', {bfx}, ...
            'bfy', {bfy}, ...
            'fx', fx, ...
            'fy', fy);

        PCView('update', view, dados_view);

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