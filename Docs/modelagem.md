# Modelagem das Expressões Regulares

Este documento detalha as expressões regulares utilizadas pelo
`TodoRecognizer` (arquivo `lib/recognizer.rb`), explicando o
funcionamento, os critérios de escolha e os casos cobertos por cada uma.

Todas as expressões foram escritas em Ruby e utilizam apenas recursos
nativos da linguagem (sem gems de data/hora ou de NLP).

---

## 1. Estratégia geral

O reconhecimento é feito em **etapas sequenciais**, removendo (substituindo
por espaços, mas mantendo o tamanho da string) cada trecho já reconhecido
antes de aplicar a próxima expressão regular. Essa estratégia evita:

- Que um número usado em uma data (`20/04/2022`) seja confundido com um
  horário (`20 04`);
- Que o símbolo `#` dentro de uma URL (`...pag1#teste?...`) seja
  interpretado como uma *tag*;
- Que dígitos de um e-mail ou URL sejam confundidos com horários ou datas.

A ordem de extração é:

1. URLs
2. E-mails
3. Tags
4. Datas (relativas → nome do mês → numéricas)
5. Horários (`às H[:MM]` → `HH:MM` → `H horas` → `HH MM`)
6. Pessoas (`com NOME [e NOME...]`)
7. Ações (verbo da lista `ACTIONS`)

---

## 2. Horários

```ruby
TIME_AS_REGEX    = /\b[àa]s\s+(\d{1,2})(?:[:h\s](\d{2}))?\s*h(?:oras?)?\b|\b[àa]s\s+(\d{1,2})(?:[:\s](\d{2}))?\b/i
TIME_COLON_REGEX = /\b(\d{1,2}):(\d{2})\b/
TIME_SPACE_REGEX = /\b(\d{1,2})\s(\d{2})\b/
TIME_HOURS_REGEX = /\b(\d{1,2})\s*h(?:oras?)?\b/i
```

### Critérios

- **`TIME_AS_REGEX`** cobre a preposição "às"/"as" (sem acento também é
  aceito), seguida de uma hora com ou sem minutos e, opcionalmente, da
  palavra "horas"/"hora"/"h". Exemplos cobertos: `às 10`, `às 10:00`,
  `às 10 30`, `às 10 horas`. É testada **primeiro** porque é o padrão
  mais específico (contém uma palavra-chave exclusiva: "às").
- **`TIME_COLON_REGEX`** cobre o formato clássico `HH:MM`, como `10:30`.
- **`TIME_HOURS_REGEX`** cobre `10 horas`, `1 hora`, `10h`. É testada
  antes do padrão `HH MM` porque exige a presença da letra `h`, tornando-a
  mais específica.
- **`TIME_SPACE_REGEX`** é o padrão mais genérico: dois números separados
  por um espaço (`10 30`). Por ser o mais "fraco" (poderia confundir
  números de datas), ele é testado **por último** e somente depois que
  datas já foram removidas do texto.

### Limites de fronteira (`\b`)

O uso de `\b` (word boundary) garante que números dentro de outros tokens
(por exemplo, o ano `2022` de uma data já removida) não sejam reaproveitados
acidentalmente.

---

## 3. Datas e dias

```ruby
RELATIVE_DATE_REGEX = /\b(depois\s+de\s+amanh[ãa]|amanh[ãa]|hoje)\b/i
FULL_DATE_REGEX     = /\b(\d{1,2})\s*(?:de\s+)?(janeiro|fevereiro|...|dezembro)\s*(?:de\s+)?(\d{4})?\b/i
NUMERIC_DATE_REGEX  = /\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/
```

### Critérios

- **`RELATIVE_DATE_REGEX`** identifica expressões relativas à data atual:
  `hoje`, `amanhã` e `depois de amanhã`. É verificada **primeiro** pois
  são as expressões mais específicas (palavras completas, sem ambiguidade
  numérica). A data final é calculada somando 0, 1 ou 2 dias à data de
  referência (`Date.today`, por padrão).
- **`FULL_DATE_REGEX`** identifica datas com o **nome do mês por extenso**.
  A partícula `de` foi tornada **opcional** tanto antes do nome do mês
  quanto antes do ano, para cobrir as variações pedidas no enunciado:
  - `28 de Fevereiro` → dia=28, mês=fevereiro, ano=ausente (usa o ano atual)
  - `13 de agosto de 2021` → dia=13, mês=agosto, ano=2021
  - `18 agosto` → dia=18, mês=agosto, ano=ausente
  - `18 de agosto 2023` → dia=18, mês=agosto, ano=2023

  A lista de meses (`MONTHS`) é gerada dinamicamente e interpolada na
  expressão regular (`MONTHS_PATTERN`), evitando repetição de código.
  A comparação é feita com a flag `/i`, então `Fevereiro`, `fevereiro` e
  `FEVEREIRO` são todos aceitos.

- **`NUMERIC_DATE_REGEX`** identifica datas no formato `dd/mm` ou
  `dd/mm/aaaa` (também aceita ano com 2 dígitos, ex: `30/01/22`, que é
  normalizado para `2022`). Quando o ano não é informado, assume-se o ano
  da data de referência.

### Por que essa ordem?

Se a verificação de data numérica (`dd/mm`) fosse feita antes da relativa,
não haveria problema, pois os padrões não se sobrepõem. Porém, ao colocar
as expressões relativas primeiro, garantimos que palavras como "hoje" e
"amanhã" — que não contêm dígitos — sejam tratadas com prioridade e de
forma independente de qualquer número presente na frase.

Após o reconhecimento, a data é convertida para um objeto `Date` do Ruby
(usando `Date.new(ano, mes, dia)`) **apenas para formatar a saída** no
padrão `dd/mm/aaaa` e para calcular `hoje + N dias`. Essa é a única
"inteligência de calendário" usada — nenhuma gem externa de datas é
necessária, pois `Date` faz parte da biblioteca padrão do Ruby (`require
'date'`).

---

## 4. Tags

```ruby
TAG_REGEX = /#[\p{L}\p{N}_]+/
```

### Critérios

- Uma tag começa com `#` seguido por um ou mais caracteres que sejam
  **letras** (`\p{L}`, incluindo letras acentuadas como `ç`, `ã`, etc.),
  **números** (`\p{N}`) ou `_`.
- Cobre `#casa`, `#trabalho`, `#financas`, `#saude`, etc.
- **Importante**: as tags são extraídas **antes** das datas/horários e
  **depois** das URLs. Isso evita que o `#` presente em uma URL (ex:
  `https://sp.senac.br/pag1#teste?aula=1&teste=4`) seja reconhecido
  incorretamente como uma tag — já que a URL é removida do texto de
  trabalho antes da busca por tags.

---

## 5. URLs

```ruby
URL_REGEX = /\bhttps?:\/\/[^\s]+/i
```

### Critérios

- Reconhece o protocolo `http://` ou `https://` (o `s` é opcional, com
  `/i` para aceitar `HTTP://`).
- Após o protocolo, captura **todos os caracteres que não sejam espaço**
  (`[^\s]+`), de forma a incluir caminhos, parâmetros de query (`?`, `&`,
  `=`) e fragmentos (`#`) — como em
  `https://sp.senac.br/pag1#teste?aula=1&teste=4`.
- É a **primeira** expressão a ser avaliada, justamente para "proteger"
  caracteres especiais (`#`, `@`, dígitos) que aparecem dentro da URL e
  que, de outra forma, poderiam ser confundidos com tags, e-mails ou
  horários/datas.

---

## 6. E-mails

```ruby
EMAIL_REGEX = /\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b/
```

### Critérios

- A parte local (antes do `@`) aceita letras, números, `_`, `.`, `+` e
  `-`, cobrindo formatos como `jose.da-silva`.
- A parte do domínio (depois do `@`) aceita letras, números e `-`,
  seguido por um ou mais grupos `.algumacoisa` (cobrindo domínios com
  múltiplos níveis, como `sp.senac.br`).
- Exemplo coberto: `jose.da-silva@sp.senac.br`.
- É avaliada **depois das URLs**, pois um e-mail poderia, em tese, fazer
  parte de uma URL (ex: `mailto:`), embora isso não seja exigido pelo
  enunciado — a ordem apenas reforça a robustez do reconhecedor.

---

## 7. Ações e Pessoas

```ruby
PEOPLE_REGEX  = /\bcom\s+([A-ZÀ-Ý][\p{L}]*(?:\s+e\s+[A-ZÀ-Ý][\p{L}]*)*)/
ACTION_REGEX  = /\b(agendar|marcar|ligar|reuniao|reunião|...)\b/i
```

### Pessoas

- O critério escolhido para identificar uma **pessoa** é a presença da
  palavra **"com"** seguida de um ou mais nomes próprios. Um nome próprio
  é reconhecido por **começar com letra maiúscula** (incluindo
  maiúsculas acentuadas, como `É`, `Á`, `Ú`), seguida por letras
  minúsculas/maiúsculas.
- Para cobrir múltiplas pessoas (`reunião com Pedro e João`), o grupo
  captura repetições de `e NOME`, e o resultado é dividido (`split`) na
  palavra `" e "`, retornando uma lista (`["Pedro", "João"]`).
- Exemplos cobertos: `agendar com Pedro`, `marcar com José`,
  `reunião com Maria`, `reunião com Pedro e João`.

### Ações

- A lista `ACTIONS` contém os verbos sugeridos no enunciado e alguns
  adicionais (`agendar`, `marcar`, `ligar`, `reunião`, `encontro`,
  `visitar`, `entregar`, `enviar`, `revisar`, `comprar`, `pagar`,
  `avisar`, `confirmar`, `lembrar`, `buscar`, `estudar`, `treinar`,
  `conversar`, entre outros).
- A expressão `ACTION_REGEX` é montada dinamicamente a partir dessa
  lista (`ACTIONS_PATTERN = ACTIONS.join('|')`), facilitando a
  manutenção: para adicionar um novo verbo basta incluí-lo no array
  `ACTIONS`.
- A busca é feita com `/i` (case-insensitive) e `\b` (word boundary),
  de modo que tanto `Agendar` quanto `agendar` sejam reconhecidos, mas
  não palavras que apenas **contenham** o verbo como substring (ex:
  "agendado" não seria confundido com "agendar", pois o `\b` exige que a
  palavra termine ali).
- A ação é avaliada **por último**, depois de remover do texto tudo o que
  já foi reconhecido (datas, horários, pessoas etc.), reduzindo a chance
  de falsos positivos.

---

## 8. Resumo das decisões de modelagem

| Elemento  | Estratégia                                                         | Por quê |
|-----------|---------------------------------------------------------------------|---------|
| URL       | Capturar tudo após `http(s)://` até o próximo espaço               | URLs podem conter `#`, `@`, dígitos e `/` que confundiriam outras regexes |
| E-mail    | `usuário@domínio.tld`, aceitando `.`, `_`, `+`, `-`                  | Formato padrão de e-mail, cobre `jose.da-silva@sp.senac.br` |
| Tag       | `#` + letras/números/`_` (com suporte a acentos)                    | Simplicidade e cobertura de acentuação |
| Data relativa | `hoje`, `amanhã`, `depois de amanhã`                            | Palavras-chave fixas, sem ambiguidade |
| Data por extenso | dia + (de)? + mês + (de)? + (ano)?                            | "de" opcional cobre todas as variações pedidas |
| Data numérica | `dd/mm(/aaaa)?`                                                  | Formato comum em agendas |
| Horário "às" | `às`/`as` + hora + (min)? + (horas)?                              | Padrão mais específico, testado primeiro |
| Horário `HH:MM` | dois números separados por `:`                                  | Formato universal de relógio |
| Horário "X horas" | número + `h`/`hora(s)`                                       | Cobre `10 horas`, `1 hora` |
| Horário `HH MM` | dois números separados por espaço                                | Padrão mais genérico, testado por último |
| Pessoa    | `com` + Nome (maiúscula inicial) + (`e` + Nome)*                    | "com" é o conector mais natural em português |
| Ação      | lista fechada de verbos, `\b` + `/i`                                | Fácil de estender, evita falsos positivos em substrings |
