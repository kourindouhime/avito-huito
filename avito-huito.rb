#!/usr/bin/env ruby

# encoding: utf-8

# TODO: 
#
# 1. Delay between requests
# 3. Notifier options (only sold, only new or both)

require 'rubygems'
require 'nokogiri'
require 'open-uri'
require 'openssl'
require 'yaml'
require 'net/smtp'
require 'slop'
require 'dkim'

@opts = Slop.parse do |o|
  o.integer '-f', '--first', 'First page (1)', default: 1
  o.integer '-l', '--last', 'Last page (100)', default: 100
  o.integer '-a', '--min_price', 'Min price (0)', default: 0
  o.integer '-b', '--max_price', 'Max price (5000)', default: 5000
  o.string '-e', '--exclude', 'Exclude "String" ("")', default: ""
  o.string '-s', '--storage', 'Storage path (storage.yml)', default: "storage.yml"
  o.string '-c', '--category', 'Category URL string ("moskva/telefony/iphone")', default: "moskva/telefony/iphone"
  o.string '-d', '--dkim_selector', 'DKIM selector ("mail")', default: "mail"
  o.string '-k', '--dkim_key', 'DKIM private key path ("private.pem")', default: "private.pem"
  o.string '-t', '--to', 'To: email@example.com ("me@yoshi.tk")', default: "me@yoshi.tk"
  o.string '-F', '--from', 'From: avito@yourdomain.com ("avito@yoshi.tk")', default: "avito@yoshi.tk"
  o.string '-S', '--subject', 'Email subject prefix ("Avito-Huito: ")', default: "Avito-Huito: "
  o.integer '-u', '--user', '0 = All, 1 = Private, 2 = Companies (0)', default: 0
  o.boolean '-D', '--no_dkim', 'Disable DKIM (-)'
  o.boolean '-v', '--verbose', 'Verbose mode (-)'
  o.on '--version', 'Show current version (0.2)' do
    abort("Avito-Huito 0.2")
  end
end

@exclude_words = ""
@opts[:exclude].split(" ").each { |a| @exclude_words += " !#{a}" }
@mail = "To: #{@opts[:to]}\nFrom: #{@opts[:from]}\nMIME-Version: 1.0\nContent-type: text/html\nSubject: #{@opts[:subject]}#{@opts.arguments[0]}\n\n"

if (ARGV.length == 0) || (@opts.arguments.length == 0)
  abort(@opts.to_s)
end

@colors_to_destroy_eyes = [:light_black, :light_red, :light_green, :light_yellow, :light_blue, :light_magenta, :light_cyan, :light_white]

def opn_pag
  page_start = @opts[:first]
  page_end = @opts[:last]

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
    if page_start.nil? && (storage_array.length > 1) && (storage_array[0].length > 0)
      page_start = storage_array[1][0]-1
      page_end = storage_array[1][1]+1 if page_end.nil?
    end
  else
    avito_populate_old = []
  end
  avito_populate = []

  pages = []

  for i in page_start..page_end do
    begin
      addr = "https://m.avito.ru/#{@opts[:category]}?bt=0&i=1&s=1&user=#{@opts[:user]}&p=#{i}&q=#{(@opts.arguments[0]+@exclude_words).split(' ').join('+')}"
      puts "Querying: #{addr}" if @opts[:verbose]
      page = Nokogiri::HTML(open(URI.escape(addr), {ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE}))
      u = page.xpath('//article[@data-item-premium=0]')-page.css('.item-highlight')
      break if u.length == 0
      u.each do |s|
        include_this = true
        price = s.css("div.item-price")[0].content.gsub(/\p{Space}/,'').to_i
        url = s.css("a.item-link")[0].values[0]
        title = s.css("span.header-text")[0].content
        img = s.css("span.pseudo-img/@style").first.value.gsub(/.*url\(\/\//, "http://").gsub(/\).*/, "").gsub("140x105", "640x480")
        include_this = false if (price > @opts[:max_price]) || (price < @opts[:min_price])
        if include_this
          avito_populate.push([url, price, title, img])
          pages[0] = i if pages[0].nil?
          pages[1] = i
        end
      end
    rescue
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

opn_pag