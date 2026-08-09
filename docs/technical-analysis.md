# Análise técnica

## Resumo

Este documento registra uma investigação de falha intermitente em uma porta USB-C/Thunderbolt do Lenovo Yoga S740-14IIL. O objetivo é preservar evidências e permitir que outras pessoas comparem seus casos; não é uma prova formal da causa raiz.

O resultado mais forte foi:

~~~text
UcsiControl.exe Send 0 10003
        |
        +-- UCSI CONNECTOR_RESET soft
        |
        +-- USB-C voltou a enumerar o hub/monitor
~~~

O reset ocorreu sem reiniciar o Windows e sem desligamento físico completo.

## Arquitetura observada

O caminho relevante no Windows era:

~~~text
Aplicações / PnP
      |
      v
UcmCx / UcmUcsiCx
      |
      v
UcmUcsiAcpiClient.sys
      |
      v
ACPI\USBC000\0
      |
      v
implementação UCSI no firmware/EC
      |
      v
conector Type-C / USB-PD / Alt Mode
~~~

O dispositivo UCSI apareceu como:

~~~text
Status: OK
Class: UCM
FriendlyName: Dispositivo UCM-UCSI ACPI
InstanceId: ACPI\USBC000\0
~~~

Os drivers relacionados estavam carregados, incluindo UcmCx.sys, UcmUcsiCx.sys e UcmUcsiAcpiClient.sys. Isso reduziu a probabilidade de uma falha simples de carregamento do driver.

## Evidências PnP usadas

Com o hub funcionando, foram observados:

~~~text
USB\VID_05E3&PID_0626*
Generic SuperSpeed USB Hub

USB\VID_0B95&PID_1790*
ASIX USB to Gigabit Ethernet Family Adapter

DISPLAY\SAM730B*
Samsung via HDMI/hub
~~~

Com o cabo USB-C para DisplayPort, foi observado:

~~~text
DISPLAY\SAM730E*
Samsung via DisplayPort
~~~

Os sufixos completos dos InstanceIds variam entre enumerações. Por isso o projeto usa padrões com wildcard e não um InstanceId inteiro.

## Sequência de testes

| Teste | Observação |
| --- | --- |
| reiniciar Thunderbolt, dispositivo 8A17 | não recuperou |
| reiniciar xHCI, dispositivo 8A13 | não recuperou |
| reiniciar USB Root Hub | não recuperou |
| desabilitar/habilitar xHCI e Thunderbolt | não recuperou |
| reiniciar ACPI\USBC000\0 | não recuperou |
| UCSI PPM_RESET, comando Send 0 1 | completou, mas não recuperou |
| UCSI CONNECTOR_RESET soft, comando Send 0 10003 | recuperou imediatamente |
| tarefa automática no boot + CONNECTOR_RESET soft | ocorrência natural recuperada em 2026-08-09, sem reboot/intervenção |

O teste decisivo foi reproduzível no notebook investigado: com o hub fisicamente conectado e sem enumeração normal, o comando soft fez o hub voltar.

## Evidência de recuperação automática no boot

Em 2026-08-09, a tarefa automática encontrou uma ocorrência real durante a inicialização, sem que alguém provocasse o estado ou interviesse manualmente. A sequência registrada foi:

~~~text
UCSI: OK | ACPI\USBC000\0
Nenhuma evidência conhecida encontrada na primeira verificação.
Segunda verificação também sem os dispositivos esperados.
Enviando UCSI CONNECTOR_RESET soft: Send 0 10003
UcsiControl: Command completed successfully
UcsiControl: ErrorIndicator: 0
UcsiControl: CommandCompletedIndicator: 1
UcsiControl exit code: 0
~~~

Cerca de nove segundos depois, a enumeração PnP voltou a mostrar o `Generic SuperSpeed USB Hub`, o monitor Samsung conectado por HDMI e o adaptador ASIX USB para Gigabit Ethernet. Portanto, a conclusão de sucesso não veio apenas do código de saída do utilitário: veio da combinação entre o comando concluído e a enumeração física posterior dos dispositivos esperados.

O `ResetCompletedIndicator: 0` não contradiz essa conclusão. Para este `CONNECTOR_RESET` soft, o indicador relevante foi `CommandCompletedIndicator: 1`; a confirmação operacional foi os dispositivos reaparecerem no Windows depois do reset.

## Estado UCSI antes da recuperação

O PPM respondia a comandos. GET_CAPABILITY completava e informava um conector. Entretanto, GET_CONNECTOR_STATUS não refletia a presença esperada do hub no estado defeituoso; o caso observado reportava ConnectStatus=0.

Isso é compatível com um estado em que:

- o Windows ainda enxerga a pilha UCSI;
- o controlador não está completamente indisponível;
- o conector lógico não completou a transição de conexão;
- o PnP não recebe a enumeração normal do hub;
- um reset do conector força uma nova negociação.

“Compatível” aqui é uma interpretação técnica, não uma confirmação de que esse é o único mecanismo interno.

## O que não foi provado

Não foi provado que:

- todos os Yoga S740 têm o mesmo defeito;
- a origem seja necessariamente BIOS, EC, PPM, controlador Type-C ou hardware;
- o reset seja permanente;
- o reset seja seguro em todos os cenários de carregamento e vídeo;
- a ausência de um dispositivo PnP seja suficiente para diagnosticar a falha quando nada está conectado;
- o comando substitua uma atualização de BIOS ou reparo físico.
- a recuperação automática funcione em todos os boots, topologias, docks ou modelos.

## ACPI e investigação de firmware

Foram examinados elementos ACPI relacionados à plataforma, incluindo referências a TXHC, TDM0, UBTC, _DSM, ECWR, ECRD, TBT0, D3C e TCON/TCOF.

Também foi observado no namespace ACPI vivo que o domínio Thunderbolt/TCSS parecia ligado durante o estado defeituoso, com valores compatíveis com um domínio de energia ativo. Isso ajudou a afastar a hipótese simples de que a falha era apenas o domínio Thunderbolt desligado.

Tentativas de ler determinadas áreas ACPI/MMIO com LiveKD falharam com páginas indisponíveis. Os avisos do debugger sobre atributos de cache não devem ser seguidos experimentalmente: ler/escrever memória física com parâmetros incorretos pode causar corrupção ou travamento. Essa linha de investigação foi interrompida.

## Por que o projeto usa recovery, não fix

O comando não altera BIOS, firmware, EC ou driver. Ele reinicializa o estado do conector por uma interface de teste UCSI exposta ao Windows. Portanto, o nome “recovery” é tecnicamente mais honesto que “fix”:

- recovery: recuperação de um estado travado;
- fix: correção permanente da causa.

Somente o primeiro foi demonstrado.

## Referências da plataforma

A documentação oficial da Microsoft descreve o cliente UCSI sobre ACPI e lista os comandos UcsiControl.exe, incluindo CONNECTOR_RESET soft como Send 0 10003:

- https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/ucsi
- https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/mutt-software-package

O repositório não redistribui os executáveis da Microsoft.

## Próximas evidências desejáveis

Para transformar um caso individual em evidência de uma falha recorrente, seriam necessários vários relatórios independentes com:

~~~text
mesmo modelo exato
mesmo sintoma
UCSI presente e OK
ConnectStatus=0 com algo conectado
Send 0 10003 recupera
~~~

Mesmo essa correlação não substituiria uma confirmação do fabricante. A evidência atual aponta para um provável estado travado na plataforma Type-C/UCSI/firmware do Yoga S740-14IIL, mas não permite atribuir categoricamente a causa à Lenovo, à Microsoft ou a um componente específico.
