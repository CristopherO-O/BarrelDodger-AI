function [x_filtrado, y_filtrado] = kalman_mario(x_medido, y_medido, confianca, reset)
    % ==============================================================
    % FILTRO DE KALMAN - RASTREAMENTO DO MARIO
    %
    % O filtro estima a posição e a velocidade do Mario.
    %
    % Estado:
    %   [X; Y; Vx; Vy]
    %
    % A cada chamada o filtro:
    %   1. Prevê onde o Mario deveria estar
    %   2. Recebe uma medição da visão computacional
    %   3. Compara a previsão com a medição
    %   4. Combina as duas informações
    % ==============================================================

    persistent estado;
    persistent incerteza;

    persistent transicao;
    persistent observacao;

    persistent ruido_processo;
    persistent ruido_medicao;

    persistent identidade;


    % ==============================================================
    % 1. INICIALIZAÇÃO
    % ==============================================================
    %
    % Isso só acontece na primeira execução ou quando reset == true.
    %
    % --------------------------------------------------------------

    if isempty(estado) || (nargin > 3 && reset == true)

        % ----------------------------------------------------------
        % Estado estimado
        %
        % [ X  ] -> posição horizontal
        % [ Y  ] -> posição vertical
        % [ Vx ] -> velocidade horizontal
        % [ Vy ] -> velocidade vertical
        % ----------------------------------------------------------
        estado = [0; 0; 0; 0];


        % ----------------------------------------------------------
        % Incerteza inicial
        %
        % Quanto maior o valor, menos confiamos na estimativa inicial.
        %
        % Aqui começamos praticamente sem saber onde o Mario está.
        % ----------------------------------------------------------
        incerteza = eye(4) * 1000;


        % ----------------------------------------------------------
        % Matriz de transição
        %
        % Descreve como acreditamos que o Mario se movimenta.
        %
        % X_novo  = X + Vx
        % Y_novo  = Y + Vy
        % Vx_novo = Vx
        % Vy_novo = Vy
        %
        % Ou seja:
        % assumimos velocidade aproximadamente constante.
        % ----------------------------------------------------------
        transicao = [1 0 1 0;
                     0 1 0 1;
                     0 0 1 0;
                     0 0 0 1];


        % ----------------------------------------------------------
        % Matriz de observação
        %
        % A visão computacional consegue medir apenas:
        %
        %   X
        %   Y
        %
        % Ela NÃO mede diretamente Vx e Vy.
        % ----------------------------------------------------------
        observacao = [1 0 0 0;
                      0 1 0 0];


        % ----------------------------------------------------------
        % Ruído do processo
        %
        % Representa o quanto o nosso modelo de movimento pode estar
        % errado.
        %
        % Exemplo:
        % o Mario pode acelerar, pular ou mudar de direção.
        % Nosso modelo de velocidade constante não representa tudo isso.
        % ----------------------------------------------------------
        ruido_processo = eye(4) * 5;


        % ----------------------------------------------------------
        % Ruído da medição
        %
        % Representa a incerteza da visão computacional.
        %
        % A posição encontrada pelo template matching não é perfeita.
        % ----------------------------------------------------------
        ruido_medicao = eye(2) * 1;


        % Matriz identidade utilizada na atualização da incerteza.
        identidade = eye(4);


        % Se essa chamada foi apenas para resetar o filtro,
        % não existe uma estimativa válida ainda.
        if nargin > 3 && reset == true
            x_filtrado = NaN;
            y_filtrado = NaN;
            return;
        end
    end


    % ==============================================================
    % 2. ETAPA DE PREVISÃO
    % ==============================================================
    %
    % Antes de olhar para a câmera, perguntamos:
    %
    % "Com base no que eu sabia anteriormente,
    %  onde o Mario deveria estar agora?"
    %
    % --------------------------------------------------------------

    estado = transicao * estado;

    % Ao prever o novo estado, também aumentamos a incerteza,
    % pois nosso modelo de movimento não é perfeito.
    incerteza = transicao * incerteza * transicao' + ruido_processo;


    % ==============================================================
    % 3. VERIFICAÇÃO DA MEDIÇÃO
    % ==============================================================
    %
    % A visão computacional fornece uma posição para o Mario.
    %
    % Porém, só vamos utilizá-la se a confiança for suficiente.
    %
    % Isso NÃO faz parte do algoritmo matemático do Kalman.
    % É uma decisão específica do sistema de visão.
    % --------------------------------------------------------------

    if confianca > 0.5

        % ----------------------------------------------------------
        % Medição obtida pela visão
        %
        % z = [X_medido;
        %      Y_medido]
        % ----------------------------------------------------------
        medicao = [x_medido; y_medido];


        % ==========================================================
        % 4. RESÍDUO / INOVAÇÃO
        % ==========================================================
        %
        % Comparamos:
        %
        %       medição real
        %              -
        %       previsão do filtro
        %
        % Se o resultado for grande, nossa previsão estava distante
        % daquilo que a visão encontrou.
        % ----------------------------------------------------------

        residuo = medicao - observacao * estado;


        % ==========================================================
        % 5. INCERTEZA DA MEDIÇÃO
        % ==========================================================
        %
        % Calculamos quanta incerteza existe no erro que acabamos
        % de observar.
        %
        % Isso leva em consideração:
        %
        %   - incerteza da nossa previsão
        %   - ruído da câmera
        % ----------------------------------------------------------

        incerteza_medicao = ...
            observacao * incerteza * observacao' + ruido_medicao;


        % ==========================================================
        % 6. GANHO DE KALMAN
        % ==========================================================
        %
        % O ganho determina quanto devemos confiar:
        %
        %   - na previsão
        %   - na nova medição
        %
        % Em termos intuitivos:
        %
        % previsão muito incerta  -> confiar mais na medição
        % medição muito incerta   -> confiar mais na previsão
        % ----------------------------------------------------------

        ganho = ...
            (incerteza * observacao') / incerteza_medicao;


        % ==========================================================
        % 7. ATUALIZAÇÃO DO ESTADO
        % ==========================================================
        %
        % Agora corrigimos nossa previsão utilizando o erro observado.
        %
        % Se a medição estiver à direita da previsão,
        % o estado será puxado nessa direção.
        % ----------------------------------------------------------

        estado = estado + ganho * residuo;


        % ==========================================================
        % 8. ATUALIZAÇÃO DA INCERTEZA
        % ==========================================================
        %
        % Depois de receber uma medição confiável,
        % passamos a ter mais certeza sobre o estado.
        % ----------------------------------------------------------

        incerteza = (identidade - ganho * observacao) * incerteza;

    end


    % ==============================================================
    % 9. RESULTADO
    % ==============================================================
    %
    % O controlador só precisa da posição filtrada.
    % Por isso retornamos X e Y do estado estimado.
    % ==============================================================

    x_filtrado = estado(1);
    y_filtrado = estado(2);


    % ==============================================================
    % 10. PROTEÇÃO CONTRA ESTIMATIVA MUITO INCERTA
    % ==============================================================
    %
    % Se a incerteza da posição ficar muito grande,
    % consideramos que não temos uma estimativa confiável.
    %
    % Nesse caso retornamos NaN para indicar:
    %
    % "Não sei onde o Mario está."
    % ==============================================================

    if incerteza(1,1) > 500
        x_filtrado = NaN;
        y_filtrado = NaN;
    end

end