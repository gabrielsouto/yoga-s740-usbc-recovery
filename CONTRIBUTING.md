# Contribuindo

Obrigado por ajudar a descobrir se este comportamento se repete em outros Lenovo Yoga S740.

## Antes de abrir uma issue

Leia o README e tente separar:

- falha de enumeração USB-C;
- falha de vídeo DisplayPort Alt Mode;
- falha de carregamento/USB Power Delivery;
- falha física ou dano no conector;
- problema de driver ou dispositivo externo.

Este projeto não deve ser usado como substituto de assistência técnica.

## Dados úteis

Inclua, quando possível:

- modelo completo e BIOS;
- versão/build do Windows;
- topologia conectada;
- status de `ACPI\USBC000\0`;
- valor de `TestInterfaceEnabled`;
- resultado dos comandos somente leitura;
- resultado de `Send 0 10003`;
- se a porta voltou sem reiniciar;
- se voltou a falhar depois.

Use `scripts/diagnose.ps1` para gerar um relatório. Revise e anonimize o arquivo antes de anexá-lo.

## Segurança

Nunca envie:

- número de série;
- nome de usuário;
- arquivos pessoais;
- tokens, chaves ou credenciais;
- cópia de `UcsiControl.exe` ou de outros binários proprietários.

Qualquer teste com reset é por conta e risco de quem o executa. Descreva exatamente o que foi feito e não recomende `810003` hard reset como primeiro passo.

## Pull requests

- mantenha o bloqueio por modelo por padrão;
- não adicione binários;
- não remova avisos de risco;
- mantenha o número de resets automáticos limitado;
- documente cada novo identificador PnP com o cenário em que ele foi observado;
- teste a sintaxe dos scripts em uma máquina de teste;
- atualize o README se alterar o comportamento de instalação ou desinstalação.
