function [mx_filtrado, my_filtrado] = kelman(mx_medido, my_medido, mscr, reset_flag)
    persistent K_X K_P K_F K_H K_Q K_R K_I;

    if isempty(K_X) || (nargin > 3 && reset_flag == true)
        K_X = [0; 0; 0; 0];      % [PosX; PosY; VelX; VelY]
        K_P = eye(4) * 1000;     % Alta incerteza inicial
        K_F = [1 0 1 0;          % Matriz de Transição (Cinemática Básica)
               0 1 0 1; 
               0 0 1 0; 
               0 0 0 1]; 
        K_H = [1 0 0 0;          % Matriz de Observação (Só lemos X e Y)
               0 1 0 0]; 
        K_Q = eye(4) * 5;        % Ruído de Processo
        K_R = eye(2) * 1;        % Ruído de Medição (Visão do template)
        K_I = eye(4);            % Identidade
        
        % Se foi apenas um reset, devolve NaN e sai
        if nargin > 3 && reset_flag == true
            mx_filtrado = NaN;
            my_filtrado = NaN;
            return;
        end
    end

    % Onde o Mario DEVERIA esta
    K_X = K_F * K_X;                     
    K_P = K_F * K_P * K_F' + K_Q;        

    % Corrigindo com a visão real
    if mscr > 0.5 
        z = [mx_medido; my_medido];
        y_res = z - K_H * K_X;           % Erro entre previsão e realidade
        S = K_H * K_P * K_H' + K_R;      
        K = K_P * K_H' * inv(S);         % Calcula o Ganho de Kalman
        
        K_X = K_X + K * y_res;           % Atualiza a posição e velocidade
        K_P = (K_I - K * K_H) * K_P;     % Reduz a incerteza
    end

    % RESULTADO FINAL
    mx_filtrado = K_X(1);
    my_filtrado = K_X(2);

    % Se a incerteza estiver muito alta, esconde o ponto
    if K_P(1,1) > 500
        mx_filtrado = NaN;
        my_filtrado = NaN;
    end
end