# APRENDIZADO POR REFORÇO NO JOGO DONKEY KONG
**Comparação entre Q-Learning tradicional e Q-Learning auxiliado por controlador heurístico**

Integrantes: Alan Vale, Cristopher Resende, Rodrigo Rezende

---

# 1. Problema

O objetivo deste trabalho é desenvolver e comparar duas abordagens de aprendizado por reforço aplicadas ao jogo Donkey Kong. O agente deve controlar o personagem Mario, buscando alcançar o topo da fase enquanto evita obstáculos.  
O problema consiste em fazer com que o agente aprenda a tomar decisões a partir das informações obtidas do próprio jogo, escolhendo ações como andar, subir escadas e pular obstáculos.  
Foram desenvolvidas duas versões do agente: uma utilizando Q-Learning tradicional, na qual as decisões são tomadas exclusivamente com base no aprendizado adquirido, e outra que permite receber sugestões de um controlador externo, que já possui uma lógica de movimentação baseada nas características do cenário.  
A proposta é investigar se a utilização dessas sugestões pode auxiliar o aprendizado e melhorar o desempenho do agente em comparação com a abordagem tradicional.  

# 2. Coleta e pré-processamento dos dados

Como o projeto utiliza aprendizado por reforço, não foi necessário utilizar um conjunto de dados previamente coletado. Os dados são obtidos durante a própria execução do jogo, por meio de um sistema de visão computacional desenvolvido anteriormente pelo grupo.  
Esse sistema identifica a posição do Mario, os obstáculos e os elementos do cenário. Também realiza o rastreamento dos objetos e estima suas trajetórias, permitindo antecipar possíveis situações de perigo.  
As posições detectadas do Mario são filtradas utilizando um filtro de Kalman, reduzindo oscilações nas estimativas causadas por possíveis erros de detecção.  
As informações obtidas são então processadas e transformadas em estados discretos, utilizados pelos algoritmos. Por exemplo, a posição do Mario em relação a uma escada é classificada como à esquerda, alinhada ou à direita. Os barris também são classificados de acordo com o nível de perigo que representam, considerando sua posição atual e trajetória prevista.  
Dessa forma, o agente trabalha com uma representação simplificada do cenário, em vez de utilizar diretamente todos os pixels da imagem.  

# 3. Escolha da técnica

A técnica escolhida foi o aprendizado por reforço, utilizando o algoritmo Q-Learning.  
Essa abordagem foi escolhida porque o problema envolve um agente que precisa tomar decisões sequenciais em um ambiente dinâmico, recebendo recompensas ou penalidades de acordo com os resultados de suas ações.  
O Q-Learning permite que o agente aprenda quais ações são mais vantajosas em cada estado do jogo, sem precisar receber previamente uma resposta correta para cada situação.  
Além da implementação tradicional, foi desenvolvida uma segunda versão que utiliza um controlador heurístico como fonte de orientação. Esse controlador analisa o cenário e recomenda ações ao agente, que pode seguir essas sugestões ou tomar decisões com base em sua própria tabela Q.  
Essa segunda abordagem permite investigar se a utilização de conhecimento prévio pode facilitar o aprendizado por reforço.  

# 4. Desenvolvimento do modelo

Foram implementadas duas versões do agente, ambas utilizando uma tabela Q para armazenar os valores associados às ações em cada estado.  

### Q-Learning tradicional

Na primeira implementação, o agente escolhe suas ações exclusivamente com base nos valores armazenados na tabela Q. Para equilibrar exploração e aproveitamento, é utilizada a estratégia epsilon-greedy, que permite escolher ações aleatórias com determinada probabilidade ou selecionar a ação com maior valor Q.  
A cada ação executada, o agente observa o novo estado e calcula uma recompensa. São consideradas recompensas pelo progresso vertical e por desviar de barris, além de bônus por vencer a fase. Também são aplicadas penalidades por estagnação, pulos desnecessários e morte.  

### Q-Learning com sugestões do controlador

Na segunda implementação, o controlador heurístico passa a ser executado continuamente, recomendando uma ação a cada quadro do jogo.  
O agente pode seguir essa recomendação ou escolher uma ação por meio de sua própria tabela Q. Estados pouco visitados recebem prioridade para seguir o controlador, enquanto estados mais conhecidos permitem maior participação do aprendizado próprio.  
Também foi adicionado um contador de visitas para cada estado e uma pequena recompensa adicional quando a ação escolhida coincide com a sugestão do controlador. A influência das sugestões diminui gradualmente durante a execução, permitindo que o agente passe a depender mais do conhecimento adquirido pela tabela Q.  
As duas implementações utilizam a mesma representação básica de estados e o mesmo conjunto de oito ações possíveis.  

# 5. Análise dos resultados

Nesta seção, serão apresentados os resultados obtidos durante a execução das duas versões do agente.  
A comparação considera aspectos como a capacidade de alcançar o final da fase, a quantidade de mortes, o tempo necessário para completar o jogo e a evolução do comportamento durante o aprendizado.  
O Q-Learning tradicional depende exclusivamente da exploração do ambiente para descobrir quais ações são mais vantajosas. Já a versão orientada possui acesso às recomendações do controlador, o que pode reduzir a quantidade de tentativas improdutivas, principalmente em estados pouco conhecidos.  

| Métrica | Q-Learning puro | Qlearn com controlador heurístico |
|---|---|---|
| Partidas realizadas |  |  |
| Vitórias |  |  |
| Taxa de vitória (%) |  |  |
| Mortes |  |  |
| Tempo médio por partida (s) |  |  |

# 6. Conclusão

O desenvolvimento deste trabalho permitiu aplicar conceitos de aprendizado por reforço em um ambiente real de jogo, integrando visão computacional, rastreamento de objetos e tomada de decisões.  
Foram desenvolvidas duas abordagens baseadas em Q-Learning: uma tradicional e outra que utiliza sugestões de um controlador heurístico. A comparação entre elas permite investigar como a utilização de conhecimento prévio pode influenciar o processo de aprendizado de um agente.  
Durante o desenvolvimento, um dos principais desafios foi transformar as informações visuais do jogo em estados que pudessem ser utilizados pelo algoritmo, além de definir recompensas capazes de incentivar comportamentos desejáveis.  
Como possíveis melhorias, destacam-se o ajuste dos parâmetros de aprendizado, o aprimoramento da representação dos estados e a realização de novos experimentos com diferentes configurações de orientação, buscando identificar a influência de cada componente no desempenho final.  
