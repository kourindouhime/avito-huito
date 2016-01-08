#!/usr/bin/env ruby

# encoding: utf-8

require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'openssl'
require 'yaml'
require 'net/smtp'
require 'slop'
require 'dkim'

@opts = Slop.parse do |o|
  o.integer '-f', '--first', 'First page', default: 1
  o.integer '-l', '--last', 'Last page', default: 50
  o.integer '-a', '--min_price', 'Min price', default: 0
  o.integer '-b', '--max_price', 'Max price', default: 5000
  o.string '-s', '--storage', 'Storage path (storage.yml)', default: "/tmp/avito-storage.yml"
  o.string '-e', '--exclude', 'Exclude vocabulary path (exclude.txt)', default: "/tmp/avito-exclude.txt"
  o.string '-c', '--category', 'Category URL string. E.g. "moskva/telefony/iphone"', default: "moskva/telefony/iphone"
  o.string '-d', '--dkim_selector', 'DKIM selector', default: "mail"
  o.string '-k', '--dkim_key', 'DKIM private key path', default: "private.pem"
  o.string '-t', '--to', 'To: email@example.com', default: "me@yoshi.tk"
  o.string '-F', '--from', 'From: avito@yourdomain.com', default: "avito@yoshi.tk"
  o.string '-S', '--subject', 'Email subject prefix', default: "Avito-Huito: "
  o.boolean '-D', '--no_dkim', 'Disable DKIM'
  o.boolean '-v', '--verbose', 'Debug mode'
  o.on '--version' do
    abort("Avito-Huito 0.1")
  end
end

@mail = "To: #{@opts[:to]}\nFrom: #{@opts[:from]}\nSubject: #{@opts[:subject]}#{@opts.arguments[0]}\n\n"


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
#@html_page = "<meta charset='UTF-8'><link rel='stylesheet' type='text/css' href='avito-huito.css'>"

def opn_pag(page_start, page_end)
  def debug(input_text)
    puts input_text if @opts[:verbose]
  end

  def pretty_print(url)
    return "https://www.avito.ru"+url
  end

  def add_to_output(good)
    debug(good[1].to_s + " " + pretty_print(good[0]))
    @mail += "<p><b>#{good[1]}</b> <a href='https://www.avito.ru#{good[0]}'>#{good[2]}</a></p>"
  end

  if File.exist?(@opts[:storage])
    avito_populate_old = YAML.load_file(@opts[:storage]).uniq
  else
    avito_populate_old = []
  end
  avito_populate = []

  for i in page_start..page_end do
    page = Nokogiri::HTML(open("https://m.avito.ru/#{@opts[:category]}?bt=0&i=1&s=1&user=1&p=#{i}&q=#{@opts.arguments[0].split(' ').join('+')}", {ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE}))
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
        #@html_page += "<div class='avito_item'><img src='#{img}'><a href='#{pretty_print(url)}'>#{title}</a><p class='price'>#{price}</p></div>" if include_this
        avito_populate.push([url, price, title, img]) if include_this
      rescue
      end
    end
  end

  File.open(@opts[:storage], 'w') { |file| file.write(avito_populate.uniq.to_yaml) }
  #puts @html_page
  #File.open("/tmp/avito-huito.html", 'w') { |file| file.write(@html_page) }
  #File.open("/tmp/avito-huito.css", 'w') { |file| file.write(File.read("avito-huito.css")) }

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
    Dkim.sign(@mail, :selector => @opts[:dkim_selector], :private_key => OpenSSL::PKey::RSA.new(open(@opts[:dkim_key]).read))
  end
end

opn_pag(@opts[:first], @opts[:last])