# Yoga S740 USB-C Recovery

[English](README.md) | **Português (Brasil)**

Uma ferramenta de diagnóstico e recuperação para um estado intermitente de USB-C/Thunderbolt observado no Lenovo Yoga S740-14IIL.

> [!WARNING]
> Este projeto é experimental, não é um driver oficial da Lenovo ou da Microsoft e não promete corrigir toda falha de USB-C. Qualquer pessoa que decidir usá-lo o fará por sua própria conta e risco. Não há garantia de recuperação, compatibilidade ou ausência de efeitos colaterais. Faça backup, mantenha um método alternativo de acesso ao computador e leia as limitações antes de executar qualquer reset.

## Resumo em uma frase

No equipamento investigado, o Windows continuava mostrando UCSI, xHCI e Thunderbolt como funcionais, mas o conector USB-C não enumerava um hub ou monitor conectado; o comando UCSI `CONNECTOR_RESET` soft, enviado por `UcsiControl.exe Send 0 10003`, recuperou a porta sem reiniciar o computador.

## O que este repositório oferece

- um procedimento manual e auditável para testar a hipótese;
- um script PowerShell de diagnóstico que gera um relatório sem arquivos pessoais;
- um script de recuperação manual;
- uma tarefa opcional no Agendador de Tarefas para verificar a porta no boot;
- detecção por assinaturas de dispositivos conhecidas e configuráveis;
- logs em `C:\ProgramData\UsbCRecovery\UsbCRecovery.log`;
- instruções para instalar e remover a automação;
- documentação da investigação, dos testes que falharam e das limitações.

O caminho recomendado é sempre: diagnóstico, teste manual, observação de mais de um ciclo de uso e somente depois instalação automática.

## Escopo validado

| Item | Evidência disponível |
| --- | --- |
| Notebook | Lenovo Yoga S740-14IIL |
| Machine Types | `81RM` (Brasil) e `81RS` |
| Sistema investigado | Windows 11 x64 |
| UCSI | `ACPI\USBC000\0`, status `OK` |
| Cliente UCSI | `UcmUcsiAcpiClient.sys` |
| BIOS observado | `BYCN39WW` |
| Evidência com hub | `USB\VID_05E3&PID_0626*` e `USB\VID_0B95&PID_1790*` |
| Evidência com DisplayPort | `DISPLAY\SAM730E*` |
| Evidência com HDMI/hub | `DISPLAY\SAM730B*` |
| Comando decisivo | `UcsiControl.exe Send 0 10003` |
| Resultado manual | recuperação imediata sem reinicialização |
| Resultado automático no boot | confirmado em 2026-08-09 durante uma ocorrência natural na inicialização |
| Resultado do comando automático | `CommandCompletedIndicator: 1`, `ErrorIndicator: 0`, código de saída `0` |
| Evidência após o reset | hub SuperSpeed, monitor Samsung via HDMI e adaptador Ethernet ASIX enumerados novamente cerca de 9 segundos depois |

Esses dados descrevem um caso validado, não uma matriz de compatibilidade. Outro Yoga S740 pode ter outro BIOS, outra topologia, outra versão do Windows ou outro defeito.

## Sintoma compatível

O caso investigado normalmente se apresentava assim:

1. o notebook iniciava com um hub USB-C ou um cabo USB-C para DisplayPort conectado;
2. a USB-C ficava sem dados/vídeo, embora o sistema continuasse iniciado;
3. os dispositivos e drivers principais ainda apareciam como `OK`;
4. desconectar e reconectar o hub não criava novos dispositivos PnP;
5. reiniciar Thunderbolt, xHCI, hub raiz ou o dispositivo UCSI não resolvia;
6. um desligamento físico completo conseguia recuperar a porta;
7. `CONNECTOR_RESET` soft recuperava a porta sem reinicialização.

Se o seu sintoma for diferente, especialmente se houver dano físico, sobretemperatura, falha de carregamento, líquido, cheiro de queimado ou erro persistente no Gerenciador de Dispositivos, não trate este projeto como solução.

## Teste manual mais seguro

### 1. Confirme o equipamento

Abra PowerShell como administrador e execute:

~~~powershell
Get-CimInstance Win32_ComputerSystem |
    Select-Object Manufacturer,Model

Get-CimInstance Win32_BIOS |
    Select-Object SMBIOSBIOSVersion,ReleaseDate

Get-PnpDevice -InstanceId 'ACPI\USBC000\0' |
    Format-Table Status,Class,FriendlyName,InstanceId -Auto
~~~

No Yoga S740-14IIL, `Win32_ComputerSystem.Model` pode retornar apenas `81RM` ou `81RS` em vez do nome comercial. Os dois Machine Types são aceitos pela validação padrão.

Não use o reset automático em outro modelo sem entender e aceitar o risco. O script bloqueia modelos não validados por padrão.

### 2. Confirme o UCSI e o modo de teste

O script espera encontrar:

~~~text
ACPI\USBC000\0
Status: OK
TestInterfaceEnabled: 1
~~~

Verifique o valor:

~~~powershell
$ucsiParameters = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\USBC000\0\Device Parameters'
Get-ItemProperty -Path $ucsiParameters -Name TestInterfaceEnabled
~~~

Se o valor não existir, o procedimento usado na investigação foi:

~~~powershell
$ucsiParameters = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\USBC000\0\Device Parameters'
New-Item -Path $ucsiParameters -Force | Out-Null
New-ItemProperty -Path $ucsiParameters -Name TestInterfaceEnabled -PropertyType DWord -Value 1 -Force
~~~

Essa alteração escreve no Registro do Windows. Faça um ponto de restauração ou exporte a chave antes, entenda como desfazer a alteração e só prossiga se aceitar o risco. O instalador deste repositório salva o valor anterior e tenta restaurá-lo na desinstalação.

### 3. Obtenha UcsiControl.exe de forma legítima

O arquivo não é distribuído neste repositório. Ele pertence ao conjunto de ferramentas de teste USB da Microsoft e pode estar disponível em uma instalação legítima do pacote MUTT/USBTest. A documentação oficial da Microsoft descreve o pacote, os comandos UCSI e o local típico usado no caso investigado:

- [USB-C Connector System Software Interface (UCSI) Driver](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/ucsi)
- [Tools in the MUTT Software Package](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/mutt-software-package)

Não baixe executáveis de sites de terceiros, não aceite versões modificadas e não coloque uma cópia proprietária no repositório sem licença de redistribuição.

O caminho esperado pelo script é:

~~~text
C:\Program Files (x86)\USBTest\x64\UcsiControl.exe
~~~

Se a instalação legítima usar outro caminho, passe-o ao instalador ou ajuste `C:\ProgramData\UsbCRecovery\UsbCRecovery.config.json`.

### 4. Faça leituras antes do reset

Com o hub ou monitor conectado e o problema presente, capture:

~~~powershell
$ucsi = 'C:\Program Files (x86)\USBTest\x64\UcsiControl.exe'

& $ucsi Send 0 6
& $ucsi Send 0 010012
& $ucsi Send 0 13
~~~

Os dois últimos comandos são usados aqui como leituras de estado/capacidade. Salve a saída para comparação. No caso investigado, `GET_CONNECTOR_STATUS` retornava `ConnectStatus=0` apesar de haver um dispositivo fisicamente conectado.

### 5. Envie o reset manual

Somente depois de confirmar o modelo, UCSI e o caminho do executável:

~~~powershell
& 'C:\Program Files (x86)\USBTest\x64\UcsiControl.exe' Send 0 10003
~~~

O `10003` é o `CONNECTOR_RESET` soft para o conector 1 na sintaxe da ferramenta. Não comece pelo `810003` hard reset: o soft reset foi suficiente no caso validado e o hard reset é uma intervenção mais agressiva.

Depois aguarde alguns segundos e verifique se o hub ou monitor aparece:

~~~powershell
Get-PnpDevice -PresentOnly |
    Where-Object {
        $_.InstanceId -like 'DISPLAY\SAM730B*' -or
        $_.InstanceId -like 'DISPLAY\SAM730E*' -or
        $_.InstanceId -like 'USB\VID_05E3&PID_0626*' -or
        $_.InstanceId -like 'USB\VID_0B95&PID_1790*'
    } |
    Format-Table Status,Class,FriendlyName,InstanceId -Auto
~~~

## Instalação da recuperação automática

Use isto somente após o teste manual ser bem-sucedido e depois de aceitar que o comando será executado como `SYSTEM` no boot.

~~~powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\install.ps1 -EnableTestInterface
~~~

O instalador:

- copia os scripts para `C:\ProgramData\UsbCRecovery`;
- grava os scripts instalados como UTF-8 com BOM para compatibilidade com Windows PowerShell 5.1;
- cria o arquivo de configuração;
- salva o valor anterior de `TestInterfaceEnabled` e preserva esse estado original em reinstalações;
- opcionalmente define `TestInterfaceEnabled=1`;
- cria a tarefa `USB-C Recovery - Yoga S740`;
- executa com conta `SYSTEM` e nível elevado;
- espera 30 segundos;
- verifica os dispositivos conhecidos;
- espera mais 10 segundos se não encontrar evidência;
- envia no máximo um `CONNECTOR_RESET` automático por inicialização;
- espera 8 segundos e registra o resultado.

Se o executável estiver em outro caminho:

~~~powershell
.\scripts\install.ps1 -EnableTestInterface -UcsiControlPath 'D:\Ferramentas\USBTest\x64\UcsiControl.exe'
~~~

### Recuperação automática confirmada durante uma falha real no boot

Em 2026-08-09, a tarefa instalada recuperou a porta automaticamente durante uma ocorrência natural do problema na inicialização. Não houve reboot nem intervenção manual. A tarefa encontrou `ACPI\USBC000\0` com status `OK`, mas os dispositivos USB-C esperados estavam ausentes na primeira e na segunda verificação. Em seguida, enviou:

~~~text
UcsiControl.exe Send 0 10003
~~~

A ferramenta informou `Command completed successfully`, `ErrorIndicator: 0`, `CommandCompletedIndicator: 1` e código de saída `0`. Cerca de nove segundos depois, o Windows enumerou novamente o `Generic SuperSpeed USB Hub`, o monitor Samsung via HDMI e o adaptador USB para Gigabit Ethernet ASIX esperados. Isso confirma o caminho de recuperação automática neste caso observado; não é uma correção universal nem uma garantia para outros sistemas.

`ResetCompletedIndicator: 0` não invalida esse resultado. Para esse comando, a evidência relevante de conclusão foi `CommandCompletedIndicator: 1` junto com a enumeração física/PnP posterior dos dispositivos USB-C.

Por padrão, o instalador aceita `81RM`, `81RS` e `*Yoga S740-14IIL*`. Para uma investigação consciente em outro modelo, a validação pode ser desativada, mas isso aumenta o risco:

~~~powershell
.\scripts\install.ps1 -EnableTestInterface -SkipModelValidation
~~~

Não use essa opção apenas para contornar um erro sem entender a causa.

## Uso manual após a instalação

Quando a USB-C travar durante o uso:

~~~powershell
& 'C:\ProgramData\UsbCRecovery\reset-usbc.ps1'
~~~

Esse comando ignora a detecção de hub/monitor e envia diretamente o reset soft, mas ainda verifica o modelo, o dispositivo UCSI, o executável e `TestInterfaceEnabled`.

Para gerar um relatório:

~~~powershell
& 'C:\ProgramData\UsbCRecovery\diagnose.ps1'
~~~

O relatório inclui modelo, BIOS, UCSI, drivers relacionados, configuração, assinaturas e comandos UCSI de leitura. Ele não coleta arquivos do usuário e não deve ser publicado sem revisão.

## Detecção configurável

O arquivo:

~~~text
C:\ProgramData\UsbCRecovery\UsbCRecovery.config.json
~~~

contém as assinaturas que representam uma USB-C saudável no caso validado:

~~~json
{
  "Signatures": [
    "DISPLAY\\SAM730B*",
    "DISPLAY\\SAM730E*",
    "USB\\VID_05E3&PID_0626*",
    "USB\\VID_0B95&PID_1790*"
  ]
}
~~~

O detector considera suficiente encontrar qualquer uma delas. Isso é deliberadamente específico: procurar qualquer hub USB seria perigoso, porque pode haver hubs internos ou dispositivos USB que não provam que a porta problemática está funcionando.

Se você usa uma topologia diferente, faça primeiro um snapshot com:

~~~powershell
Get-PnpDevice -PresentOnly |
    Select-Object Status,Class,FriendlyName,InstanceId |
    Export-Csv .\present-devices.csv -NoTypeInformation -Encoding UTF8
~~~

Altere as assinaturas somente quando souber que elas pertencem à conexão USB-C esperada.

## Logs e códigos de saída

O log fica em:

~~~text
C:\ProgramData\UsbCRecovery\UsbCRecovery.log
~~~

Para evitar ambiguidade de codificação ao lê-lo manualmente:

~~~powershell
Get-Content 'C:\ProgramData\UsbCRecovery\UsbCRecovery.log' -Encoding UTF8 -Tail 50
~~~

Os scripts instalados são gravados como UTF-8 com BOM para que o `PowerShell.exe` do Windows PowerShell 5.1 preserve corretamente caracteres acentuados nas novas entradas do log. Linhas antigas já corrompidas não são reescritas.

Os códigos principais do script são:

| Código | Significado |
| ---: | --- |
| 0 | evidência encontrada ou recuperação concluída |
| 1 | reset falhou ou evidência continuou ausente |
| 2 | pré-requisito ausente, UCSI indisponível ou modelo não validado |

O script não fica tentando indefinidamente. O objetivo é evitar um ciclo de resets no boot.

## Desinstalação

Abra PowerShell como administrador:

~~~powershell
.\scripts\uninstall.ps1
~~~

A desinstalação remove a tarefa e os arquivos de `C:\ProgramData\UsbCRecovery`. Se o instalador alterou `TestInterfaceEnabled`, ele tenta restaurar o valor anterior. Revise o log antes de apagar qualquer evidência que possa ajudar no diagnóstico.

## O que foi testado

| Intervenção | Resultado observado |
| --- | --- |
| reinício do dispositivo Thunderbolt `8A17` | não recuperou |
| reinício do controlador xHCI `8A13` | não recuperou |
| reinício do USB Root Hub | não recuperou |
| desabilitar/habilitar xHCI e Thunderbolt | não recuperou |
| reinício do dispositivo UCSI `ACPI\USBC000\0` | não recuperou |
| UCSI `PPM_RESET`, `Send 0 1` | não recuperou |
| UCSI `CONNECTOR_RESET` soft, `Send 0 10003` | recuperou imediatamente |
| verificação automática no boot seguida de `CONNECTOR_RESET` soft | recuperou naturalmente no boot em 2026-08-09; sem reboot/intervenção |

O resultado aponta para um provável estado travado na camada conector/Type-C/PD/UCSI/firmware de plataforma do Yoga S740-14IIL. Ele não prova se a causa precisa está no EC, controlador Type-C/PD, firmware da plataforma Intel, integração da Lenovo, Windows ou hardware, e não estabelece uma correção universal.

## Segurança e limites

- O script roda elevado e pode ser executado como `SYSTEM`; trate-o como software privilegiado.
- O reset pode interromper carregamento, vídeo, USB, DisplayPort Alt Mode ou negociações USB Power Delivery em andamento.
- Não há garantia de que a operação seja segura para outro notebook, dock, carregador ou controlador.
- Não distribuímos `UcsiControl.exe`, drivers, firmware, BIOS modificado ou arquivos da Microsoft.
- Não há driver de kernel neste projeto.
- Não há promessa de correção permanente: o reset recupera um estado observado, mas não altera o firmware.
- Se o notebook estiver sem nada conectado, a ausência de evidência não diferencia “porta saudável sem dispositivo” de “porta travada”; nesse caso, não instale a automação sem adaptar o detector.
- Não execute resets repetidos para tentar recuperar um hardware que apresenta sintomas elétricos ou físicos.
- Leia o código, revise as assinaturas e mantenha um plano de recuperação fora da USB-C.

## Compatibilidade e relatos

Relatos de outros Yoga S740 são bem-vindos, mas devem separar claramente:

1. modelo exato e BIOS;
2. versão do Windows;
3. dispositivo conectado;
4. estado do UCSI;
5. saída de `GET_CONNECTOR_STATUS`;
6. se o reset soft funcionou;
7. se a recuperação foi temporária ou persistente.

Não publique números de série, nomes de usuário, caminhos pessoais ou relatórios sem revisar os dados.

## Estrutura

~~~text
README.md
README.pt-BR.md
LICENSE
CONTRIBUTING.md
scripts/
  UsbCRecovery.ps1
  diagnose.ps1
  install.ps1
  reset-usbc.ps1
  uninstall.ps1
docs/
  technical-analysis.md
  troubleshooting.md
  how-we-found-it.md
.github/
  ISSUE_TEMPLATE/
    recovery-failed.yml
    same-problem.yml
~~~

## Referências oficiais

- [Lenovo Support: Yoga S740-14IIL Type 81RM](https://pcsupport.lenovo.com/br/pt/products/laptops-and-netbooks/yoga-series/yoga-s740-14iil/81rm)
- [Lenovo Support: Yoga S740-14IIL Type 81RS](https://pcsupport.lenovo.com/br/pt/products/laptops-and-netbooks/yoga-series/yoga-s740-14iil/81rs)
- [Microsoft: USB-C Connector System Software Interface (UCSI) Driver](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/ucsi)
- [Microsoft: Tools in the MUTT Software Package](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/mutt-software-package)
- [Microsoft: USB Hardware Verifier](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/how-to-retrieve-information-about-a-usb-device)

## Licença e responsabilidade

O código deste repositório é distribuído sob a licença MIT. Ferramentas da Microsoft mencionadas ou usadas pelo usuário continuam sujeitas às licenças e condições da Microsoft.

Ao executar os scripts, você reconhece que o uso é por sua conta e risco. O autor e os contribuidores não assumem responsabilidade por perda de dados, indisponibilidade, danos a dispositivos, alteração de registro, incompatibilidade, falha de recuperação ou qualquer outro efeito decorrente do uso.