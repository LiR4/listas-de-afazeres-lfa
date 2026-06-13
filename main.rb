

require_relative 'lib/recognizer'

# garantir padrao de caracteres

if RUBY_PLATFORM =~ /mingw|mswin|cygwin/i
  system('chcp 65001 > nul 2>&1')
end

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8
STDOUT.set_encoding('UTF-8')

def to_utf8(str)
  str = str.dup.force_encoding('UTF-8')
  return str if str.valid_encoding?

  %w[IBM850 Windows-1252 ISO-8859-1].each do |encoding|
    begin
      convertido = str.dup.force_encoding(encoding).encode('UTF-8')
      return convertido if convertido.valid_encoding?
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      next
    end
  end

  str.scrub('?')
end


def print_result(result)
  puts '-' * 40
  puts "Dia:      #{result.dia}"        if result.dia
  puts "Horário:  #{result.horario}"    if result.horario

  result.pessoas.each do |pessoa|
    puts "Pessoa:   #{pessoa}"
  end

  puts "Ação:     #{result.acao}" if result.acao

  result.tags.each do |tag|
    puts "Tag:      #{tag}"
  end

  result.urls.each do |url|
    puts "URL:      #{url}"
  end

  result.emails.each do |email|
    puts "Email:    #{email}"
  end

  if result.dia.nil? && result.horario.nil? && result.pessoas.empty? &&
     result.acao.nil? && result.tags.empty? && result.urls.empty? &&
     result.emails.empty?
    puts '(nenhum padrão reconhecido)'
  end
  puts '-' * 40
end

recognizer = TodoRecognizer.new

puts '== Reconhecedor de Listas de Afazeres =='
puts 'Digite uma tarefa por linha (ou "sair" para encerrar):'
puts

loop do
  print '> '
  linha = gets

  
  break if linha.nil?

  linha = to_utf8(linha)

  linha = linha.chomp
  break if linha.strip.downcase == 'sair'

  if linha.strip.empty?
    puts 'Linha vazia, tente novamente.'
    next
  end

  resultado = recognizer.parse(linha)
  print_result(resultado)
  puts
end

puts 'Fim.'