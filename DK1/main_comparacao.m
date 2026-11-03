clear variables;
close all force;
clc;
clear controlador_mario;
clear rastreia_barril;

graphics_toolkit("fltk");
pkg load image;
pkg load retro_games;

% Alterna uma tentativa completa por agente para comparar com o mesmo estado inicial.
agentes = {'hqlearn', 'qlearn_puro', 'dqn'};
nomes = {'Q-learning com controlador', 'Q-learning puro', 'Deep Q-learning (DQN)'};
mult_vel = 3;
correlacao_estimada = 0.5128;
horizonte_barril = 30;
limite_sumido = 10;
sprite_morto = 6;   % indice do template mc{6} (mario morto)
arquivo_resultados = 'resultados_comparacao.csv';

if mult_vel < 1 || mult_vel ~= fix(mult_vel)
    error('mult_vel deve ser um inteiro positivo.');
end

[jogo, startpoint] = inicializar_emulador("DK.nes");

if exist('mapa_dk_level1.mat', 'file') && ...
   exist('mc_template.mat', 'file') && ...
   exist('inimigos_template.mat', 'file')
    load('mapa_dk_level1.mat');
    load('mc_template.mat');
    load('inimigos_template.mat');
else
    [mapa, mc, inimigos] = varreduraInicial(jogo);
end

if numel(mc) < sprite_morto
    warning('mc_template.mat tem apenas %d templates (sem o sprite de morte). Apague o arquivo para regenerar.', numel(mc));
end

if exist(arquivo_resultados, 'file')
    fid = fopen(arquivo_resultados, 'a');
else
    fid = fopen(arquivo_resultados, 'w');
end
if fid < 0
    error('Nao foi possivel abrir o arquivo de resultados: %s', arquivo_resultados);
end
info_arquivo = dir(arquivo_resultados);
if isempty(info_arquivo) || info_arquivo.bytes == 0
    fprintf(fid, 'data_hora,agente,tentativa,resultado,frames,altura_inicial,melhor_altura,progresso_px,duracao_s\n');
end
fclose(fid);

fig = figure('Name', 'Comparacao Q-learning');
set(fig, 'UserData', true);
set(fig, 'KeyPressFcn', @(obj, event) strcmp(event.Key, 'escape') && set(obj, 'UserData', false));

% Exibicao simples: so a imagem do emulador, sem overlay
jogo.set_state(startpoint);
figure(fig);
himg = imshow(jogo.get_image());

tentativas = zeros(1, numel(agentes));
vitorias = zeros(1, numel(agentes));
mortes = zeros(1, numel(agentes));
progresso_total = zeros(1, numel(agentes));
indice_agente = 1;

while ishandle(fig) && get(fig, 'UserData')
    agente = agentes{indice_agente};
    tentativas(indice_agente) = tentativas(indice_agente) + 1;
    tentativa = tentativas(indice_agente);

    jogo.set_state(startpoint);
    jogo.set_input([0 0 0 0 0 0 0 0]);
    kelman(0, 0, 0, true);
    clear rastreia_barril;
    clear controlador_mario;

    frames_sem_mario = 0;
    frames_tentativa = 0;
    altura_inicial = NaN;
    melhor_altura = Inf;
    resultado = '';
    tempo_inicio = tic();

    fprintf('\nTentativa %d - %s\n', tentativa, nomes{indice_agente});

    while ishandle(fig) && get(fig, 'UserData')
        jogo.step(2 * mult_vel);
        imc = jogo.get_image();
        img = rgb2gray(imc);

        [mx_bruto, my_bruto, sprite_atual_mario, mscr] = localizar_mario(img, mc);
        [bx, by, bvx, bvy, bpx, bpy, ~, ~] = rastreia_barril(img, inimigos.barril, horizonte_barril, mapa);
        [fx, fy] = localizar_foguinho(img);
        [mx, my] = kelman(mx_bruto, my_bruto, mscr, false);

        frames_tentativa = frames_tentativa + 1;

        % Sprite de morte detectado com confianca (mc{6}). O isscalar evita
        % erro caso o localizar_mario devolva vazio quando nao acha nada.
        mario_morto = isscalar(sprite_atual_mario) && sprite_atual_mario == sprite_morto ...
                      && mscr > correlacao_estimada;

        if mscr > correlacao_estimada
            frames_sem_mario = 0;
            % Nao conta a altura do Mario morto (a animacao de morte "pula"
            % pra cima e inflaria o progresso).
            if ~mario_morto && ~isnan(my)
                if isnan(altura_inicial)
                    altura_inicial = my;
                end
                melhor_altura = min(melhor_altura, my);
            end
        else
            frames_sem_mario = frames_sem_mario + 1;
        end

        % Morte: sprite de morte (imediato) OU Mario sumiu por muitos frames (reserva)
        if mario_morto || frames_sem_mario >= limite_sumido
            resultado = 'morte';
            if mario_morto
                disp('  causa: sprite de morte detectado');
            else
                disp('  causa: Mario sumiu');
            end
            switch agente
                case 'hqlearn'
                    HQlearn(-1, 0, 0, mapa, [], [], [], [], [], [], [], []);
                case 'qlearn_puro'
                    Qlearn_puro(-1, 0, 0, mapa, [], [], [], [], [], [], [], []);
                case 'dqn'
                    DQN(-1, 0, 0, mapa, [], [], [], [], [], [], [], []);
            end
            mortes(indice_agente) = mortes(indice_agente) + 1;
            break;
        end

        switch agente
            case 'hqlearn'
                [inputs_ia, Fx, Fy] = HQlearn(mx, my, sprite_atual_mario, mapa, ...
                    bx, by, bvx, bvy, bpx, bpy, fx, fy);
            case 'qlearn_puro'
                [inputs_ia, Fx, Fy] = Qlearn_puro(mx, my, sprite_atual_mario, mapa, ...
                    bx, by, bvx, bvy, bpx, bpy, fx, fy);
            case 'dqn'
                [inputs_ia, Fx, Fy] = DQN(mx, my, sprite_atual_mario, mapa, ...
                    bx, by, bvx, bvy, bpx, bpy, fx, fy);
            otherwise
                error('Agente de comparacao desconhecido: %s', agente);
        end
        jogo.set_input(inputs_ia);

        if my < 30
            resultado = 'vitoria';
            switch agente
                case 'hqlearn'
                    HQlearn(-1, 0, 0, mapa, [], [], [], [], [], [], [], []);
                case 'qlearn_puro'
                    Qlearn_puro(-1, 0, 0, mapa, [], [], [], [], [], [], [], []);
                case 'dqn'
                    DQN(-1, 0, 0, mapa, [], [], [], [], [], [], [], []);
            end
            vitorias(indice_agente) = vitorias(indice_agente) + 1;
            break;
        end

        % Atualiza so a imagem da tela
        set(himg, 'CData', imc);

        % Progresso medio so das tentativas JA concluidas (antes dividia por
        % "tentativa", que inclui a atual e subestimava a media)
        concluidas = tentativa - 1;
        if concluidas > 0
            prog_medio = progresso_total(indice_agente) / concluidas;
        else
            prog_medio = 0;
        end
        nome_janela = sprintf('%s | tentativa %d | vitorias %d, mortes %d | progresso medio %.1f px', ...
            nomes{indice_agente}, tentativa, vitorias(indice_agente), ...
            mortes(indice_agente), prog_medio);
        set(fig, 'Name', nome_janela);
        pause(0.01 / mult_vel);
    end

    if ~isempty(resultado)
        duracao = toc(tempo_inicio);
        if isnan(altura_inicial) || isinf(melhor_altura)
            progresso = 0;
            melhor_registrada = NaN;
        else
            progresso = max(0, altura_inicial - melhor_altura);
            melhor_registrada = melhor_altura;
        end
        progresso_total(indice_agente) = progresso_total(indice_agente) + progresso;

        fid = fopen(arquivo_resultados, 'a');
        if fid < 0
            error('Nao foi possivel gravar resultados em %s.', arquivo_resultados);
        end
        fprintf(fid, '%s,%s,%d,%s,%d,%.2f,%.2f,%.2f,%.2f\n', ...
            datestr(now, 'yyyy-mm-dd HH:MM:SS'), agente, tentativa, resultado, ...
            frames_tentativa, altura_inicial, melhor_registrada, progresso, duracao);
        fclose(fid);

        fprintf('%s: %s, %d frames, progresso %.1f px, %.1f s\n', ...
            nomes{indice_agente}, resultado, frames_tentativa, progresso, duracao);
        indice_agente = mod(indice_agente, numel(agentes)) + 1;
    end
end

if ishandle(fig)
    close(fig);
end
disp(['Comparacao encerrada. Resultados salvos em ' arquivo_resultados]);