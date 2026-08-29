# Troubleshooting

## Aviso principal

Todos os procedimentos deste documento são por conta e risco da pessoa que os executa. O reset é enviado por uma ferramenta privilegiada e pode interromper USB, vídeo, carregamento ou negociação USB Power Delivery. Não execute o procedimento em caso de dano físico, líquido, calor anormal, cheiro de queimado ou falha elétrica.

## O script diz que o modelo não é validado

Verifique:

~~~powershell
Get-CimInstance Win32_ComputerSystem |
    Select-Object Manufacturer,Model
~~~

O Yoga S740-14IIL pode aparecer em `Win32_ComputerSystem.Model` apenas pelo Machine Type. A Lenovo identifica este modelo como `81RM` no Brasil e `81RS` em outros mercados. Por isso, a configuração padrão aceita exatamente:

~~~text
81RM
81RS
*Yoga S740-14IIL*
~~~

Se um Yoga S740-14IIL retornar `81RM` ou `81RS`, isso é esperado e não deve exigir `-SkipModelValidation`.

Se o modelo for realmente outro, isso não significa que o reset seja seguro. A validação pode ser desativada somente para uma investigação consciente:

~~~powershell
.\scripts\install.ps1 -EnableTestInterface -SkipModelValidation
~~~

Não use essa opção em produção sem dados que justifiquem o teste.

## O log mostra `inÃ­cio`, `verificaÃ§Ã£o` ou outros acentos corrompidos

A tarefa agendada usa `PowerShell.exe`, isto é, Windows PowerShell 5.1. Essa versão pode interpretar arquivos UTF-8 sem BOM usando a página de código ANSI do sistema. Quando isso acontece, os próprios textos do script já chegam corrompidos ao arquivo de log.

A partir da correção de 2026-08-29, o instalador grava os scripts em `C:\ProgramData\UsbCRecovery` explicitamente como UTF-8 com BOM antes de criar a tarefa agendada. Reinstale a versão atual para substituir os scripts instalados.

Ao consultar o log manualmente, também é seguro informar a codificação explicitamente:

~~~powershell
Get-Content 'C:\ProgramData\UsbCRecovery\UsbCRecovery.log' -Encoding UTF8 -Tail 50
~~~

Linhas antigas que já foram gravadas com texto corrompido não são reescritas; a correção vale para novas execuções.

## UCSI não encontrado ou não está OK

Verifique:

~~~powershell
Get-PnpDevice -InstanceId 'ACPI\USBC000\0' |
    Format-List Status,Class,FriendlyName,InstanceId
~~~

Se o dispositivo não existir ou estiver com erro, pare. O projeto não deve mascarar um problema de driver ou hardware usando reset de conector.

## UcsiControl.exe não encontrado

O repositório não contém o executável. Instale ou obtenha o pacote MUTT/USBTest por uma fonte legítima da Microsoft e configure o caminho:

~~~powershell
.\scripts\install.ps1 -EnableTestInterface -UcsiControlPath 'C:\caminho\legitimo\UcsiControl.exe'
~~~

Não use downloads aleatórios, cópias de terceiros ou executáveis modificados.

## TestInterfaceEnabled está ausente

O caminho usado na investigação foi:

~~~powershell
$path = 'HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\USBC000\0\Device Parameters'
Get-ItemProperty -Path $path -Name TestInterfaceEnabled
~~~

O instalador pode definir o valor:

~~~powershell
.\scripts\install.ps1 -EnableTestInterface
~~~

Isso altera o Registro. Faça backup e compreenda o procedimento de reversão antes de continuar. A desinstalação tenta restaurar o valor anterior salvo na configuração.

## O reset completou, mas nada voltou

Possibilidades:

- o caso não é o mesmo;
- o dispositivo ainda está demorando para enumerar;
- a assinatura configurada não representa sua topologia;
- há uma falha independente no hub, cabo, monitor ou carregador;
- a recuperação exige desligamento completo;
- o firmware ou hardware tem outra falha.

Verifique manualmente:

~~~powershell
Get-PnpDevice -PresentOnly |
    Sort-Object InstanceId |
    Select-Object Status,Class,FriendlyName,InstanceId
~~~

Gere também:

~~~powershell
.\scripts\diagnose.ps1
~~~

Não repita o reset em loop.

## A recuperação automática funcionou no boot

Em 2026-08-09, uma ocorrência natural foi recuperada pela tarefa automática sem reboot nem intervenção manual. O log mostrou `ACPI\USBC000\0` como `OK`, ausência dos dispositivos esperados nas duas verificações, `UcsiControl.exe Send 0 10003`, `Command completed successfully`, `ErrorIndicator: 0`, `CommandCompletedIndicator: 1` e código de saída `0`. Cerca de nove segundos depois, o hub SuperSpeed, o monitor Samsung via HDMI e o adaptador Ethernet ASIX apareceram novamente.

Ao interpretar esse resultado, não trate `ResetCompletedIndicator: 0` isoladamente como falha. Para esse comando, `CommandCompletedIndicator: 1` indica que o comando foi concluído; a validação operacional é a enumeração PnP posterior dos dispositivos esperados. Ainda assim, isso confirma apenas este caso observado e não promete recuperação em todos os boots ou equipamentos.

## O script resetou quando nada estava conectado

Isso ocorre quando a configuração assume que um hub/monitor sempre estará presente. A ausência de evidência não prova que a porta está travada se nada foi conectado.

Nesse cenário:

- desinstale a tarefa automática;
- ou remova as assinaturas que não representam sua topologia;
- ou use apenas o reset manual;
- ou desenvolva uma lógica que só atue quando o usuário confirmar que um dispositivo deveria estar presente.

## A tarefa não aparece

Verifique como administrador:

~~~powershell
Get-ScheduledTask -TaskName 'USB-C Recovery - Yoga S740' |
    Select-Object TaskName,State,TaskPath
~~~

Se o logon automático estiver desabilitado ou as políticas locais bloquearem tarefas como SYSTEM, a tarefa pode não iniciar. Execute o script manualmente para separar falha de instalação de falha de recuperação.

## Como desfazer

~~~powershell
.\scripts\uninstall.ps1
~~~

Se o script não puder ser executado, remova a tarefa pelo Agendador de Tarefas e restaure o valor do Registro usando o backup feito antes da instalação. Não remova chaves inteiras de enumeração de dispositivos sem saber exatamente o que está fazendo.

## Quando procurar assistência

Procure assistência técnica ou suporte Lenovo se:

- a porta não fornece energia em nenhum cenário;
- houver sinais físicos de dano;
- a falha persistir depois de reinstalação/atualização suportada;
- o UCSI estiver ausente ou com erro permanente;
- o reset só funcionar temporariamente e o problema estiver piorando;
- houver perda de dados, travamentos ou desligamentos.

O comportamento observado é mais compatível com um provável issue de firmware/plataforma Type-C/UCSI do Yoga S740-14IIL do que com uma conclusão categórica sobre Lenovo ou Microsoft. O reset é um workaround de recuperação e não substitui atualização suportada, diagnóstico de hardware ou reparo.
