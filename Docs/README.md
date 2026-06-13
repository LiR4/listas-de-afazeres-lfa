# Reconhecedor: Sistema de Gestão de Listas de Afazeres

Trabalho da disciplina de **Linguagens Formais e Autômatos**: um
**reconhecedor baseado em Expressões Regulares**, implementado em **Ruby**,
capaz de ler uma linha de texto descrevendo um afazer e extrair
informações estruturadas: horário, data, pessoas, ação, tags, URLs e
e-mails.

---

## 1. O problema resolvido

Aplicativos de listas de tarefas (como Todoist e Remember The Milk)
permitem que o usuário digite uma tarefa em **linguagem natural**, por
exemplo:

```
Agendar com José reunião às 10:00 amanhã #trabalho
```

e o sistema extrai automaticamente os elementos relevantes dessa frase:

```
Dia:      22/03/2022
Horário:  10:00
Pessoa:   José
Ação:     agendar
Tag:      #trabalho
```

O objetivo deste trabalho é implementar esse tipo de reconhecimento
**usando exclusivamente expressões regulares**, sem o uso de gems de
processamento de linguagem natural ou de manipulação de datas (além da
biblioteca padrão `date` do Ruby, usada apenas para calcular `hoje + N
dias` e formatar a data de saída).

---

## 2. Modelagem e teoria envolvida

### 2.1 Expressões Regulares como Autômatos Finitos

Toda expressão regular pode ser convertida em um **Autômato Finito**
(determinístico ou não-determinístico) capaz de reconhecer a linguagem
regular descrita por ela. Neste trabalho, cada padrão de interesse
(horário, data, tag, URL, e-mail, pessoa e ação) foi modelado como uma
**linguagem regular separada**, ou seja, como uma expressão regular
independente — o que corresponde, na teoria de autômatos, a vários
**reconhecedores especializados** sendo aplicados sequencialmente sobre
a mesma entrada.

### 2.2 Estratégia de reconhecimento sequencial

Como a linha de texto pode conter **múltiplos padrões simultaneamente**
(uma data, um horário, uma pessoa, uma ação e uma tag, todos na mesma
frase), não é suficiente usar uma única expressão regular "monolítica".
A estratégia adotada foi:

1. Aplicar cada expressão regular, na ordem que vai do **padrão mais
   específico** para o **mais genérico**;
2. Sempre que um padrão é reconhecido, o trecho correspondente é
   "apagado" (substituído por espaços, mantendo o tamanho da string) do
   texto de trabalho;
3. Isso evita que um mesmo trecho da entrada seja capturado por mais de
   um padrão (por exemplo, o `#` de uma URL sendo confundido com uma
   tag, ou os números de uma data sendo confundidos com um horário).

A ordem de aplicação é:

```
URL → E-mail → Tag → Data (relativa → por extenso → numérica)
    → Horário (às H[:MM] → HH:MM → H horas → HH MM)
    → Pessoa (com NOME [e NOME...]) → Ação
```

Essa ideia — várias linguagens regulares aplicadas em sequência sobre a
mesma entrada, "consumindo" partes dela — é análoga ao funcionamento de
um **analisador léxico (lexer)**, no qual cada token é reconhecido por
um autômato finito específico.

### 2.3 Por que não usar bibliotecas de data?

O enunciado proíbe o uso de gems que reconheçam datas (como `Chronic` ou
similares). Por isso, toda a interpretação de datas — nomes de meses em
português, formato `dd/mm/aaaa`, datas relativas (`hoje`, `amanhã`,
`depois de amanhã`) — é feita **inteiramente via expressões regulares**.
A classe `Date` da biblioteca padrão do Ruby (`require 'date'`) é usada
apenas como **utilitário de formatação e aritmética de calendário**
(somar dias, formatar `dd/mm/aaaa`), e não para *reconhecer* o padrão —
o reconhecimento (ou seja, decidir *se* e *onde* existe uma data no
texto, e quais são seus componentes dia/mês/ano) é responsabilidade
exclusiva das expressões regulares.

Para a documentação detalhada de cada expressão regular, com a
justificativa de cada escolha e os casos cobertos, veja
[`Docs/modelagem.md`](modelagem.md).

---

## 3. Estrutura do projeto

```
.
├── Docs/
│   └── README.md                 # este arquivo
├── main.rb                    # programa principal (entrada via teclado)
├── lib/
│   └── recognizer.rb          # classe TodoRecognizer (todas as regex)
├── spec/
│   └── recognizer_test.rb     # bateria de testes automatizados
└── Docs/
    └── modelagem.md           # documentação detalhada das regex
```

---

## 4. Explicação básica do código

### 4.1 `lib/recognizer.rb` — classe `TodoRecognizer`

- **Constantes** `MONTHS` e `ACTIONS`: listas/mapas usados para montar
  dinamicamente as expressões regulares de datas e ações.
- **Constantes de regex** (`URL_REGEX`, `EMAIL_REGEX`, `TAG_REGEX`,
  `RELATIVE_DATE_REGEX`, `FULL_DATE_REGEX`, `NUMERIC_DATE_REGEX`,
  `TIME_AS_REGEX`, `TIME_COLON_REGEX`, `TIME_SPACE_REGEX`,
  `TIME_HOURS_REGEX`, `PEOPLE_REGEX`, `ACTION_REGEX`): cada uma reconhece
  um padrão específico (ver `docs/modelagem.md`).
- **`Result`**: um `Struct` que representa a saída estruturada
  (`dia`, `horario`, `pessoas`, `acao`, `tags`, `urls`, `emails`).
- **`#initialize(reference_date:)`**: permite informar a "data de hoje"
  usada para calcular `hoje`/`amanhã`/`depois de amanhã`. Por padrão,
  usa `Date.today`.
- **`#parse(text)`**: método principal. Recebe a linha de texto e
  retorna um `Result` com todos os elementos reconhecidos, aplicando as
  expressões na ordem descrita na seção 2.2.
- **Métodos privados**:
  - `blank_out` / `blank_out_match`: "apagam" um trecho já reconhecido,
    preservando o tamanho da string.
  - `extract_date`: tenta, em ordem, `RELATIVE_DATE_REGEX`,
    `FULL_DATE_REGEX` e `NUMERIC_DATE_REGEX`; converte o resultado para
    `dd/mm/aaaa`.
  - `resolve_relative_date`: converte `hoje`/`amanhã`/`depois de amanhã`
    em um objeto `Date` (data de referência + 0/1/2 dias).
  - `extract_time`: tenta, em ordem, `TIME_AS_REGEX`, `TIME_COLON_REGEX`,
    `TIME_HOURS_REGEX` e `TIME_SPACE_REGEX`; formata o resultado como
    `HH:MM`.
  - `extract_people`: usa `PEOPLE_REGEX` e separa múltiplos nomes
    (`"Pedro e João"` → `["Pedro", "João"]`).
  - `extract_action`: usa `ACTION_REGEX` para encontrar o verbo de ação.

### 4.2 `main.rb` — programa interativo

- Configura a codificação para UTF-8 (entrada/saída), para suportar
  acentuação.
- Em um laço (`loop`), lê uma linha do teclado (`gets`).
- Se o usuário digitar `sair` (ou pressionar Ctrl+D), o programa termina.
- Caso contrário, chama `TodoRecognizer#parse` e imprime o resultado de
  forma estruturada (`print_result`), no formato:

```
Dia:      22/03/2022
Horário:  10:00
Pessoa:   José
Ação:     agendar
Tag:      #trabalho
```


## 5. Como executar

É necessário ter o **Ruby** instalado (testado com Ruby 3.2).

### 5.1 Programa interativo

```bash
ruby main.rb
```

O programa solicitará linhas de texto pelo teclado. Exemplo de sessão:

```
== Reconhecedor de Listas de Afazeres ==
Digite uma tarefa por linha (ou "sair" para encerrar):

> Agendar com José reunião às 10:00 amanhã #trabalho
----------------------------------------
Dia:      22/03/2022
Horário:  10:00
Pessoa:   José
Ação:     agendar
Tag:      #trabalho
----------------------------------------

> sair
Fim.
```

## 6. Exemplos de entradas suportadas

| Categoria | Exemplos |
|-----------|----------|
| Horário   | `10:30`, `10 30`, `10 horas`, `1 hora`, `às 10` |
| Data      | `28 de Fevereiro`, `13 de agosto de 2021`, `30/01`, `20/04/2022`, `hoje`, `amanhã`, `depois de amanhã`, `18 agosto`, `18 de agosto 2023` |
| Tag       | `#casa`, `#trabalho`, `#saude` |
| URL       | `https://sp.senac.br/pag1#teste?aula=1&teste=4` |
| E-mail    | `jose.da-silva@sp.senac.br` |
| Ação/Pessoa | `agendar com Pedro`, `marcar com José`, `reunião com Maria`, `reunião com Pedro e João` |

---

## 7. Limitações conhecidas

- Apenas **um** valor de cada tipo (data/horário) é extraído por linha —
  se a frase contiver duas datas, apenas a primeira reconhecida é
  utilizada.
- A lista de verbos de ação (`ACTIONS`) é fixa, mas pode ser facilmente
  estendida em `lib/recognizer.rb`.
- O reconhecimento de "pessoa" depende do conector `com` seguido de um
  nome iniciado por letra maiúscula (convenção comum em português para
  nomes próprios).
