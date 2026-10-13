# Donkey Kong (NES) – Agente Autônomo com Visão Computacional e Q-Learning

Projeto em **GNU Octave** que joga a fase 1 de *Donkey Kong* (NES) sozinho. O jogo roda em um emulador dentro do Octave (pacote `retro_games`). A cada frame o programa **lê a imagem da tela**, localiza o Mario, os barris e o foguinho, e decide qual botão apertar, usando uma máquina de estados e/ou **Q-Learning**.

## Como funciona

```
Emulador (frame) ─► Visão computacional ─► Filtro de Kalman ─► IA (controlador / Q-Learning) ─► Botões do NES
```

1. **Inicialização** (`inicializar_emulador.m`): carrega a ROM, passa pelo menu e pela intro e salva um *save state* (`startpoint`) usado para reiniciar a fase rapidamente.
2. **Mapeamento da fase** (`varreduraInicial.m`): na primeira execução detecta plataformas e escadas por cor, extrai os templates do Mario e dos barris e salva tudo em arquivos `.mat`.
3. **Percepção** a cada frame:
   - `localizar_mario.m`: detecta o Mario por cor + correlação cruzada normalizada (`normxcorr2`) com os templates; também informa o sprite atual (direita, esquerda, subindo escada…).
   - `kelman.m`: filtro de Kalman (posição + velocidade) que suaviza a posição do Mario.
   - `rastreia_barril.m`: detecta e rastreia até 6 barris com Kalman, estima a velocidade e **prevê a trajetória** futura de cada um.
   - `localizar_foguinho.m`: detecta o foguinho por cor.
4. **Decisão** (`main_DK.m` escolhe o modo em `modo_ia`):
   - `controlador_mario.m`: máquina de estados fixa (`ANDANDO` / `SUBINDO`) que sobe escadas e pula barris, sem aprendizado.
   - `Qlearn.m`: Q-Learning tabular. A cada frame escolhe entre 6 ações: **sobe, desce, esquerda, direita, pulo** ou **delegar ao `controlador_mario`**. Ele aprende *quando* vale usar o controlador pronto e quando agir "cru".
   - `desligado`: ninguém joga; útil para depurar a visão.
5. **Reset automático**: se o Mario some por 10 frames (morreu) ou chega ao topo (`my < 30`), o estado salvo é recarregado e uma nova tentativa começa. O Q-Learning é avisado do reset para aplicar a penalidade/recompensa correta.

### Recompensas do Q-Learning (valores padrão)

| Evento | Valor |
|---|---|
| Subir de altura | +2 por pixel |
| Desviar de barril (pulo certeiro) | +50 |
| Vencer (chegar ao topo) | +1000 |
| Morrer | −100 |
| Pular à toa | −1 |
| Ficar parado >200 frames sem subir | −2 por frame |

Hiperparâmetros: `ALPHA=0.1`, `GAMMA=0.9`, ε-greedy com ε de 0.3 decaindo até 0.05. A tabela Q é salva em `qlearn_tabela.mat` a cada 500 frames e recarregada na próxima execução, então o aprendizado é acumulativo.

## Requisitos

- GNU Octave (com interface gráfica/toolkit `fltk`)
- Pacotes Octave:
  - `image`
  - `retro_games` (emulador NES para Octave)

```octave
pkg install -forge image
% instale o retro_games conforme a documentação do pacote
```

## Como executar

1. Abra o Octave na pasta do projeto.
2. Coloque a ROM `DK.nes` na mesma pasta (você deve possuir uma cópia legal do jogo).
3. Execute:

```octave
main_DK
```

4. Para encerrar, pressione **ESC** na janela do jogo.

## Configuração (topo de `main_DK.m`)

| Variável | Descrição | Padrão |
|---|---|---|
| `modo_ia` | `'controlador'`, `'qlearn'` ou `'desligado'` | `'qlearn'` |
| `pc_view` | Mostra lado a lado o jogo e a "visão do computador" (plataformas, escadas, Mario, barris, trajetórias previstas, foguinho) | `true` |
| `auto_reset` | Reinicia automaticamente quando o Mario morre | `true` |
| `horizonte_barril` | Frames à frente para prever a trajetória dos barris | `30` |
| `correlacao_estimada` | Limiar de correlação para considerar o Mario "visível" (não use menos de 0.5128) | `0.5128` |

> Para treinar mais rápido, defina `pc_view = false`: a renderização extra deixa o loop mais lento.

## Estrutura dos arquivos

| Arquivo | Função |
|---|---|
| `main_DK.m` | Programa principal: loop de jogo, resets e visualização |
| `inicializar_emulador.m` | Carrega a ROM, pula a intro e salva o estado inicial |
| `varreduraInicial.m` | Gera o mapa da fase e os templates (primeira execução) |
| `localizar_mario.m` | Detecção do Mario por correlação de templates |
| `localizar_foguinho.m` | Detecção do foguinho |
| `rastreia_barril.m` | Rastreamento e previsão de trajetória dos barris (Kalman) |
| `kelman.m` | Filtro de Kalman para a posição do Mario |
| `controlador_mario.m` | IA baseada em regras (máquina de estados) |
| `Qlearn.m` | IA com Q-Learning tabular |
| `mapa_dk_level1.mat`, `mc_template.mat`, `inimigos_template.mat` | Mapa e templates gerados pela varredura inicial |
| `qlearn_tabela.mat` | Tabela Q aprendida (persistente entre execuções) |
| `DK.nes` | ROM do jogo |

## Dicas

- **Regerar mapa/templates:** apague `mapa_dk_level1.mat`, `mc_template.mat` e `inimigos_template.mat`; a varredura roda de novo na próxima execução.
- **Recomeçar o aprendizado do zero:** apague `qlearn_tabela.mat`.
- **Depurar a visão:** use `modo_ia = 'desligado'` com `pc_view = true`.

## Aviso

Projeto educacional, sem afiliação com a Nintendo. *Donkey Kong* é propriedade da Nintendo; a ROM não é distribuída com a licença deste projeto.
