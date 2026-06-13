

require 'date'


class TodoRecognizer
  
  MONTHS = {
    'janeiro' => 1, 'fevereiro' => 2, 'marco' => 3, 'março' => 3,
    'abril' => 4, 'maio' => 5, 'junho' => 6, 'julho' => 7,
    'agosto' => 8, 'setembro' => 9, 'outubro' => 10,
    'novembro' => 11, 'dezembro' => 12
  }.freeze

  
  ACTIONS = %w[
    agendar marcar ligar reunir reuniao reunião encontrar encontro
    almocar almoçar jantar visitar entregar enviar revisar comprar
    pagar avisar confirmar lembrar buscar estudar treinar conversar
  ].freeze

  MONTHS_PATTERN  = MONTHS.keys.uniq.join('|')
  ACTIONS_PATTERN = ACTIONS.uniq.join('|')

  # ---------------------------------------------------------------------
  # Expressões regulares
  # ---------------------------------------------------------------------

  # URL: começa com http:// ou https:// e segue até encontrar um espaço.
  URL_REGEX = /\bhttps?:\/\/[^\s]+/i.freeze

  # E-mail: caracteres comuns de usuário (letras, números, ., _, -, +),
  # seguidos de @, domínio e extensão.
  EMAIL_REGEX = /\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b/.freeze

  # Tag: # seguido de letras/números/underscore (inclui acentuação).
  TAG_REGEX = /#[\p{L}\p{N}_]+/.freeze

  # Datas relativas: hoje, amanhã, depois de amanhã.
  RELATIVE_DATE_REGEX = /\b(depois\s+de\s+amanh[ãa]|amanh[ãa]|hoje)\b/i.freeze

  # Data completa com nome do mês. Cobre:
  #   "28 de Fevereiro"        -> dia=28, mes=Fevereiro
  #   "13 de agosto de 2021"   -> dia=13, mes=agosto, ano=2021
  #   "18 agosto"              -> dia=18, mes=agosto
  #   "18 de agosto 2023"      -> dia=18, mes=agosto, ano=2023
  # As partículas "de" são opcionais tanto antes do mês quanto antes do ano.
  FULL_DATE_REGEX = /\b(\d{1,2})\s*(?:de\s+)?(#{MONTHS_PATTERN})\s*(?:de\s+)?(\d{4})?\b/i.freeze

  # Data numérica: dd/mm ou dd/mm/yyyy (ou yy).
  NUMERIC_DATE_REGEX = /\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/.freeze

  # Horário no formato "às H", "às H:MM" ou "às H horas".
  TIME_AS_REGEX = /\b[àa]s\s+(\d{1,2})(?:[:h\s](\d{2}))?\s*h(?:oras?)?\b|\b[àa]s\s+(\d{1,2})(?:[:\s](\d{2}))?\b/i.freeze

  # Horário no formato "HH:MM".
  TIME_COLON_REGEX = /\b(\d{1,2}):(\d{2})\b/.freeze

  # Horário no formato "HH MM" (dois números separados por espaço).
  TIME_SPACE_REGEX = /\b(\d{1,2})\s(\d{2})\b/.freeze

  # Horário no formato "H horas" ou "H hora" (ex: "1 hora", "10 horas").
  TIME_HOURS_REGEX = /\b(\d{1,2})\s*h(?:oras?)?\b/i.freeze

  # Pessoas: "com NOME" ou "com NOME e NOME2 ...". Nomes começam com
  # letra maiúscula (com ou sem acento).
  PEOPLE_REGEX = /\bcom\s+([A-ZÀ-Ý][\p{L}]*(?:\s+e\s+[A-ZÀ-Ý][\p{L}]*)*)/.freeze

  # Ação: um dos verbos da lista ACTIONS, em qualquer posição da frase.
  ACTION_REGEX = /\b(#{ACTIONS_PATTERN})\b/i.freeze

  Result = Struct.new(
    :dia, :horario, :pessoas, :acao, :tags, :urls, :emails,
    keyword_init: true
  )

  def initialize(reference_date: Date.today)
    @reference_date = reference_date
  end


  def parse(text)
    working = text.dup

    urls = working.scan(URL_REGEX)
    working = blank_out(working, URL_REGEX)

    emails = working.scan(EMAIL_REGEX)
    working = blank_out(working, EMAIL_REGEX)

    tags = working.scan(TAG_REGEX)
    working = blank_out(working, TAG_REGEX)

    dia, working = extract_date(working)
    horario, working = extract_time(working)
    pessoas, working = extract_people(working)
    acao = extract_action(working)

    Result.new(
      dia: dia,
      horario: horario,
      pessoas: pessoas,
      acao: acao,
      tags: tags,
      urls: urls,
      emails: emails
    )
  end

  private

  # Substitui todas as ocorrências de +regex+ em +text+ por espaços,
  # preservando o tamanho da string (evita que outras expressões
  # regulares "casem" acidentalmente com trechos já reconhecidos).
  def blank_out(text, regex)
    text.gsub(regex) { |m| ' ' * m.length }
  end

  # -------------------------------------------------------------------
  # Datas
  # -------------------------------------------------------------------
  def extract_date(text)
    if (m = RELATIVE_DATE_REGEX.match(text))
      date = resolve_relative_date(m[1])
      return [format_date(date), blank_out_match(text, m)]
    end

    if (m = FULL_DATE_REGEX.match(text))
      day   = m[1].to_i
      month = MONTHS[m[2].downcase]
      year  = m[3] ? m[3].to_i : @reference_date.year
      date  = safe_date(year, month, day)
      return [format_date(date), blank_out_match(text, m)] if date
    end

    if (m = NUMERIC_DATE_REGEX.match(text))
      day   = m[1].to_i
      month = m[2].to_i
      year  = m[3] ? normalize_year(m[3]) : @reference_date.year
      date  = safe_date(year, month, day)
      return [format_date(date), blank_out_match(text, m)] if date
    end

    [nil, text]
  end

  def resolve_relative_date(word)
    normalized = word.downcase.gsub('amanha', 'amanhã')
    case normalized
    when /depois\s+de\s+amanh[ãa]/ then @reference_date + 2
    when /amanh[ãa]/                then @reference_date + 1
    when /hoje/                     then @reference_date
    end
  end

  def safe_date(year, month, day)
    Date.new(year, month, day)
  rescue ArgumentError
    nil
  end

  def normalize_year(year_str)
    return year_str.to_i if year_str.length == 4

    # Anos com dois dígitos: assume século 2000.
    2000 + year_str.to_i
  end

  def format_date(date)
    date.strftime('%d/%m/%Y')
  end

  # -------------------------------------------------------------------
  # Horários
  # -------------------------------------------------------------------
  def extract_time(text)
    if (m = TIME_AS_REGEX.match(text))
      hour, minute = pick_time_groups(m)
      return [format_time(hour, minute), blank_out_match(text, m)]
    end

    if (m = TIME_COLON_REGEX.match(text))
      return [format_time(m[1], m[2]), blank_out_match(text, m)]
    end

    if (m = TIME_HOURS_REGEX.match(text))
      return [format_time(m[1], 0), blank_out_match(text, m)]
    end

    if (m = TIME_SPACE_REGEX.match(text))
      return [format_time(m[1], m[2]), blank_out_match(text, m)]
    end

    [nil, text]
  end

  # TIME_AS_REGEX possui dois grupos alternativos (com/sem a palavra
  # "horas"), por isso escolhemos o primeiro par de grupos preenchido.
  def pick_time_groups(m)
    if m[1]
      [m[1], m[2]]
    else
      [m[3], m[4]]
    end
  end

  def format_time(hour, minute)
    h = hour.to_i
    mi = minute.nil? ? 0 : minute.to_i
    format('%02d:%02d', h, mi)
  end

  # -------------------------------------------------------------------
  # Pessoas
  # -------------------------------------------------------------------
  def extract_people(text)
    if (m = PEOPLE_REGEX.match(text))
      people = m[1].split(/\s+e\s+/)
      return [people, blank_out_match(text, m)]
    end

    [[], text]
  end

  # -------------------------------------------------------------------
  # Ações
  # -------------------------------------------------------------------
  def extract_action(text)
    m = ACTION_REGEX.match(text)
    m && m[1].downcase
  end

  # Apaga (substitui por espaços) o trecho correspondente ao MatchData
  # +m+ dentro de +text+, preservando os índices das demais ocorrências.
  def blank_out_match(text, m)
    full = m[0]
    text.sub(full) { ' ' * full.length }
  end
end
