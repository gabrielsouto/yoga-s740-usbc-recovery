# Como chegamos ao comando

Este é o diário resumido da descoberta, organizado para que outra pessoa consiga reproduzir a lógica sem repetir testes cegamente.

## 1. Sintoma inicial

O notebook ocasionalmente iniciava com um hub USB-C ou cabo USB-C para DisplayPort conectado, mas a conexão não aparecia no Windows. Um power cycle completo costumava devolver a funcionalidade.

A primeira hipótese foi uma falha no controlador Thunderbolt ou no xHCI.

## 2. Identificação dos controladores

Foram comparados dispositivos presentes e seus estados. Thunderbolt, xHCI, UCSI e os drivers principais apareciam normalmente. Reiniciar os dispositivos Thunderbolt e xHCI não recuperou a porta.

Isso diferenciou:

~~~text
controlador ausente ou driver quebrado
        versus
controlador presente, mas conector sem enumeração
~~~

## 3. Comparação com e sem hub

Foi criado um snapshot PnP com o hub ausente e outro com o hub conectado. No estado defeituoso, a conexão física não resultou na enumeração esperada de novos dispositivos.

Quando tudo funcionava, a comparação revelou IDs estáveis o suficiente para detectar a conexão:

- hub Genesys Logic: USB\VID_05E3&PID_0626;
- Ethernet ASIX: USB\VID_0B95&PID_1790;
- monitor Samsung por HDMI: DISPLAY\SAM730B;
- monitor Samsung por DisplayPort: DISPLAY\SAM730E.

## 4. Migração do foco para UCSI

O dispositivo ACPI\USBC000\0 estava presente e OK, com:

- UcmCx.sys;
- UcmUcsiCx.sys;
- UcmUcsiAcpiClient.sys.

A conclusão provisória foi que o Windows ainda conseguia conversar com a implementação UCSI, então valia testar uma operação específica de UCSI.

## 5. PPM_RESET não foi suficiente

Foi enviado:

~~~powershell
& $ucsi Send 0 1
~~~

O comando completou, mas a porta continuou sem enumerar o hub.

Isso foi importante: simplesmente reinicializar o PPM não corrigiu o estado observado.

## 6. CONNECTOR_RESET soft resolveu

Foi enviado:

~~~powershell
& $ucsi Send 0 10003
~~~

O hub voltou imediatamente. Não foi necessário reiniciar o Windows, o xHCI, o Thunderbolt ou fazer um hard reset UCSI.

## 7. Recuperação automática confirmada em ocorrência natural

Em 2026-08-09, a tarefa instalada encontrou o problema durante a inicialização normal, sem reboot adicional e sem intervenção manual. O UCSI continuava em `OK` (`ACPI\USBC000\0`), mas os dispositivos esperados não apareceram na primeira verificação nem após a espera da segunda verificação.

A tarefa enviou `UcsiControl.exe Send 0 10003` e registrou `Command completed successfully`, `ErrorIndicator: 0`, `CommandCompletedIndicator: 1` e código de saída `0`. Cerca de nove segundos depois, o `Generic SuperSpeed USB Hub`, o monitor Samsung via HDMI e o adaptador Ethernet ASIX foram enumerados novamente pelo Windows.

Essa foi uma recuperação automática confirmada em uma ocorrência natural do defeito, não uma demonstração obtida por reboot ou por uma ação manual. `ResetCompletedIndicator: 0` não invalida o resultado: a conclusão relevante foi `CommandCompletedIndicator: 1`, reforçada pela enumeração física/PnP posterior.

## 8. Automatização

Como o notebook normalmente inicia com o hub ou o monitor conectados, uma ausência de qualquer assinatura conhecida após a enumeração é uma sinalização útil. A automação foi desenhada para:

1. esperar a inicialização;
2. verificar uma vez;
3. esperar novamente;
4. verificar uma segunda vez;
5. enviar no máximo um reset;
6. registrar o resultado.

Se a máquina inicia frequentemente sem nada conectado, essa suposição deixa de ser válida e a automação deve ser evitada ou personalizada.

## 9. Conclusão responsável

O resultado foi um workaround reproduzível em uma máquina específica, com uma recuperação automática confirmada em uma ocorrência natural no boot. A evidência é compatível com um provável issue de firmware/plataforma Type-C/UCSI do Yoga S740-14IIL, mas não permite atribuir categoricamente a causa à Lenovo, à Microsoft ou a um componente específico. O repositório documenta o caminho até ele para que outras pessoas possam testar a mesma hipótese com seus próprios dados, sem transformar uma observação individual em promessa universal.
