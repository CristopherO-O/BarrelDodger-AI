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
   - `Qlearn.m` e `NQlearn.m`: agentes existentes do projeto; `NQlearn.m` usa o `controlador_mario.m` como sugestão.
   - `Qlearn_puro.m`: cópia independente que escolhe entre 8 ações usando somente a tabela Q: **sobe, desce, esquerda, direita, pulo, direita+pulo, esquerda+pulo** ou **nenhuma tecla**. Não chama o controlador.
   - `controlador_mario.m`: máquina de estados fixa (`ANDANDO` / `SUBINDO`), disponível apenas nos modos legados.
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

Hiperparâmetros da cópia pura: `ALPHA=0.1`, `GAMMA=0.9`, ε-greedy com ε de 0.3 decaindo até 0.05. Sua tabela é salva em `qlearn_tabela_puro.mat` a cada 500 frames e ao terminar cada tentativa. `NQlearn` persiste em `qlearn_tabela_v2.mat`, também a cada 500 frames, em vitórias e ao terminar tentativas. Essas tabelas são os modelos aprendidos; não são pesos de uma rede neural.

O projeto já guarda as tabelas Q para continuar o treinamento, mas antes não registrava um resumo comparável de cada tentativa. `main_comparacao.m` alterna tentativas completas dos dois agentes no mesmo emulador, sempre começando do mesmo save state, e acrescenta os resultados a `resultados_comparacao.csv` (agente, vitória/morte, frames, altura alcançada, progresso e duração). Como usa um emulador único, eles não aparecem simultaneamente lado a lado: a janela mostra um agente por tentativa. As tabelas Q continuam separadas.

## Requisitos

- GNU Octave (com interface gráfica/toolkit `fltk`)
- `octave-dev` no Ubuntu/Debian, para compilar a ponte C++ (`libretro_bridge.oct`) do pacote `retro_games`
- Pacotes Octave:
  - `image`
  - `retro_games` (emulador NES para Octave)
- ROM legal `DK.nes`, colocada dentro de `DK1/`

## Instalação do Octave e do pacote `retro_games`

O diretório fonte do pacote já acompanha o projeto em `BarrelDodger-AI/retro_games-0.1.0/`, ao lado da pasta `DK1/`. O `octave-dev` fornece as ferramentas de desenvolvimento usadas para compilar a ponte nativa do emulador; depois, o Octave registra o pacote com `pkg`.

No Ubuntu/Debian, instale o Octave e as ferramentas de desenvolvimento:

```bash
sudo apt update
sudo apt install octave octave-dev
```

Abra o Octave com a pasta de trabalho em `BarrelDodger-AI/DK1/` e instale o pacote local que está no diretório acima:

```octave
pkg install -local ../retro_games-0.1.0
pkg install -forge image
pkg load image
pkg load retro_games
which load_rom
```

## Como executar

1. Abra o Octave na pasta do projeto.
2. Coloque a ROM `DK.nes` na mesma pasta (você deve possuir uma cópia legal do jogo).
3. Execute:

```octave
main_DK
```

Para comparar o agente guiado pelo controlador (`NQlearn`) com o Q-learning puro, execute:

```octave
main_comparacao
```

O comparador alterna uma tentativa de cada agente. Pressione **ESC** na janela para encerrar. Abra `resultados_comparacao.csv` em uma planilha para comparar as tentativas; cada nova execução acrescenta linhas ao arquivo.

## Configuração (topo de `main_DK.m`)

| Variável | Descrição | Padrão |
|---|---|---|
| `modo_ia` | `'nqlearn'` (versão atual), `'qlearn_puro'` (cópia independente), `'qlearn'`, `'controlador'` ou `'desligado'` | `'nqlearn'` |
| `pc_view` | Mostra lado a lado o jogo e a "visão do computador" (plataformas, escadas, Mario, barris, trajetórias previstas, foguinho) | `true` |
| `auto_reset` | Reinicia automaticamente quando o Mario morre | `true` |
| `horizonte_barril` | Frames à frente para prever a trajetória dos barris | `30` |
| `correlacao_estimada` | Limiar de correlação para considerar o Mario "visível" (não use menos de 0.5128) | `0.5128` |

> Para treinar mais rápido, defina `pc_view = false`: a renderização extra deixa o loop mais lento.

## Estrutura dos arquivos

| Arquivo | Função |
|---|---|
| `main_DK.m` | Programa principal: loop de jogo, resets e visualização |
| `main_comparacao.m` | Alterna os agentes com controlador e puro e registra métricas por tentativa |
| `inicializar_emulador.m` | Carrega a ROM, pula a intro e salva o estado inicial |
| `varreduraInicial.m` | Gera o mapa da fase e os templates (primeira execução) |
| `localizar_mario.m` | Detecção do Mario por correlação de templates |
| `localizar_foguinho.m` | Detecção do foguinho |
| `rastreia_barril.m` | Rastreamento e previsão de trajetória dos barris (Kalman) |
| `kelman.m` | Filtro de Kalman para a posição do Mario |
| `Qlearn.m` | IA Q-learning existente (mantida sem alteração de comportamento) |
| `Qlearn_puro.m` | Cópia independente com Q-learning sem controlador |
| `NQlearn.m` | Versão experimental de Q-learning guiada pelo controlador |
| `controlador_mario.m` | IA baseada em regras, usada apenas nos modos legados |
| `mapa_dk_level1.mat`, `mc_template.mat`, `inimigos_template.mat` | Mapa e templates gerados pela varredura inicial |
| `qlearn_tabela_puro.mat` | Tabela Q da cópia pura (persistente entre execuções) |
| `qlearn_tabela.mat`, `qlearn_tabela_v2.mat` | Tabelas dos agentes existentes |
| `DK.nes` | ROM do jogo |

## Dicas

- **Regerar mapa/templates:** apague `mapa_dk_level1.mat`, `mc_template.mat` e `inimigos_template.mat`; a varredura roda de novo na próxima execução.
- **Executar a cópia Q-learning pura:** altere `modo_ia` para `'qlearn_puro'` no topo de `main_DK.m`.
- **Recomeçar o aprendizado puro do zero:** apague `qlearn_tabela_puro.mat`.
- **Recomeçar os resultados da comparação:** apague `resultados_comparacao.csv`.
- **Depurar a visão:** use `modo_ia = 'desligado'` com `pc_view = true`.

## Aviso

Projeto educacional, sem afiliação com a Nintendo. *Donkey Kong* é propriedade da Nintendo; a ROM não é distribuída com a licença deste projeto.
