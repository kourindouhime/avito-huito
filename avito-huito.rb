#!/usr/bin/env ruby

# encoding: utf-8

# TODO: 
#
# 1. Delay between requests
# 2. All, user=1 or user=2

require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'openssl'
require 'yaml'
require 'net/smtp'
require 'slop'
require 'dkim'

@opts = Slop.parse do |o|
  o.integer '-f', '--first', 'First page'
  o.integer '-l', '--last', 'Last page'
  o.integer '-a', '--min_price', 'Min price', default: 0
  o.integer '-b', '--max_price', 'Max price', default: 5000
  o.string '-s', '--storage', 'Storage path (storage.yml)', default: "storage.yml"
  o.string '-e', '--exclude', 'Exclude vocabulary path (exclude.txt)', default: "exclude.txt"
  o.string '-c', '--category', 'Category URL string. E.g. "moskva/telefony/iphone"', default: "moskva/telefony/iphone"
  o.string '-d', '--dkim_selector', 'DKIM selector', default: "mail"
  o.string '-k', '--dkim_key', 'DKIM private key path', default: "private.pem"
  o.string '-t', '--to', 'To: email@example.com', default: "me@yoshi.tk"
  o.string '-F', '--from', 'From: avito@yourdomain.com', default: "avito@yoshi.tk"
  o.string '-S', '--subject', 'Email subject prefix', default: "Avito-Huito: "
  o.integer '-u', '--user', '0 = All, 1 = Private, 2 = Companies', default: 0
  o.boolean '-D', '--no_dkim', 'Disable DKIM'
  o.boolean '-v', '--verbose', 'Verbose mode'
  o.on '--version' do
    abort("Avito-Huito 0.1")
  end
end

@mail = "To: #{@opts[:to]}\nFrom: #{@opts[:from]}\nMIME-Version: 1.0\nContent-type: text/html\nSubject: #{@opts[:subject]}#{@opts.arguments[0]}\n\n"

if (ARGV.length == 0) || (@opts.arguments.length == 0)
  abort(@opts.to_s)
end

@exclude_words = []

File.open(@opts[:exclude], "r") do |f|
  f.each_line do |line|
    @exclude_words.push(line.strip)
  end
end

@colors_to_destroy_eyes = [:light_black, :light_red, :light_green, :light_yellow, :light_blue, :light_magenta, :light_cyan, :light_white]

def opn_pag(page_start, page_end)
  def debug(input_text)
    puts input_text if @opts[:verbose]
  end

  def pretty_print(url)
    return "https://www.avito.ru"+url
  end

  def add_to_output(good)
    debug(good[1].to_s + " " + pretty_print(good[0]))
    @mail += "<p>#{good[3]} <b>#{good[1]}</b> <a href='https://www.avito.ru#{good[0]}'>#{good[2]}</a></p>"
  end

  if File.exist?(@opts[:storage])
    storage_array = YAML.load_file(@opts[:storage])
    avito_populate_old = storage_array[0].uniq
    if page_start.nil? && (storage_array.length > 1)
      page_start = storage_array[1][0]-1
      page_end = storage_array[1][1]+1 if page_end.nil?
    end
  else
    avito_populate_old = []
  end
  avito_populate = []

  pages = []

  for i in page_start..page_end do
    page = Nokogiri::HTML(open("https://m.avito.ru/#{@opts[:category]}?bt=0&i=1&s=1&user=#{@opts[:user]}&p=#{i}&q=#{@opts.arguments[0].split(' ').join('+')}", {ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE}))
    u = page.xpath('//article[@data-item-premium=0]')-page.css('.item-highlight')
    u.each do |s|
      begin
        include_this = true
        price = s.css("div.item-price")[0].content.gsub(/\p{Space}/,'').to_i
        url = s.css("a.item-link")[0].values[0]
        title = s.css("span.header-text")[0].content
        img = s.css("span.pseudo-img/@style").first.value.gsub(/.*url\(\/\//, "http://").gsub(/\).*/, "").gsub("140x105", "640x480")
        @exclude_words.each do |word|
          if url.include? word
            include_this = false
          end
        end
        include_this = false if (price > @opts[:max_price]) || (price < @opts[:min_price])
        if include_this
          avito_populate.push([url, price, title, img])
          pages[0] = i if pages[0].nil?
          pages[1] = i
        end
      rescue
      end
    end
  end

  File.open(@opts[:storage], 'w') { |file| file.write([avito_populate.uniq, pages].to_yaml) }

  debug("Sold items:")
  @mail += "<h1>Sold items:</h1>"

  (avito_populate_old-avito_populate).each do |k|
    add_to_output(k)
  end

  debug("New items:")
  @mail += "<h1>New items:</h1>"

  (avito_populate-avito_populate_old).each do |k|
    add_to_output(k)
  end

  if !@opts[:no_dkim]
    @mail = Dkim.sign(@mail, :selector => @opts[:dkim_selector], :private_key => OpenSSL::PKey::RSA.new(open(@opts[:dkim_key]).read), :domain => @opts[:from].split("@")[1])
  end

  if ((avito_populate_old-avito_populate).length > 0) || ((avito_populate-avito_populate_old).length > 0)
    Net::SMTP.start('127.0.0.1') do |smtp|
      smtp.send_message @mail, @opts[:from], @opts[:to]
    end
  else
    debug("No updates")
  end
end

opn_pag(@opts[:first], @opts[:last])