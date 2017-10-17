#!/usr/bin/env ruby

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'rubygems'
require 'commander/import'
require 'rest-client'
require 'json'
require 'csv'
require 'yaml'
require 'qif'
require 'teller/export/version'
require 'fileutils'

program :name, 'teller-export'
program :version, Teller::Export::VERSION
program :description, 'Generate QIF or CSV from Teller'

command :qif do |c|
  c.syntax = 'teller-export qif [options]'
  c.summary = ''
  c.description = ''
  c.option '--directory STRING', String, 'The directory to save this file'
  c.option '--token STRING', String, 'The token from Teller'
  c.action do |args, options|
    options.default directory: "#{File.dirname(__FILE__)}/tmp"
    accounts(options.token).each do |account|
      path = full_path(options.directory, account, :qif)
      Qif::Writer.open(path, type = 'Bank', format = 'dd/mm/yyyy') do |qif|
        transactions(options.token, account).each do |transaction|
          qif << Qif::Transaction.new(
            date: Date.parse(transaction['date']),
            amount: transaction['amount'],
            memo: transaction['description'],
            payee: transaction['counterparty']
          )
        end
      end

      puts "#{path} => #{account['currency']} #{account['balance']}"
    end

  end
end

command :csv do |c|
  c.syntax = 'teller-export csv [options]'
  c.summary = ''
  c.description = ''
  c.option '--directory STRING', String, 'The directory to save this file'
  c.option '--token STRING', String, 'The token from Teller'
  c.action do |args, options|
    options.default directory: "#{File.dirname(__FILE__)}/tmp"
    accounts(options.token).each do |account|
      path = full_path(options.directory, account, :csv)
      CSV.open(path, "wb") do |csv|
        csv << [:date, :description, :amount, :balance]
        transactions(options.token, account).each do |transaction|
          csv << [
            Date.parse(transaction['date']).strftime("%d/%m/%y"),
            transaction['counterparty'],
            transaction['amount'],
            transaction['running_balance']
          ]
        end
      end

      puts "#{path} => #{account['currency']} #{account['balance']}"
    end
  end
end

command :balance do |c|
  c.syntax = 'teller-export balance [options]'
  c.option '--token STRING', String, 'The token from Teller'
  c.action do |args, options|
    currency_replacements = { 'GBP' => '£' }
    accounts(options.token).each do |account|
      currency_output = currency_replacements[account['currency']] || account['currency']
      puts "#{account['institution'].capitalize} #{account['name']}:"
      puts "Account Number: #{account['account_number']}"
      puts "Sort Code: #{account['sort_code']}"
      puts "Balance: #{currency_output}#{account['balance']}"
      puts '---'
    end
  end
end

def full_path(directory, account, extension)
  account_name = account['name'].gsub(/^.*(\\|\/)/, '').gsub(/[^0-9A-Za-z.\-]/, '_').downcase
  account_name += "_#{account['account_number']}"

  full_directory = [directory, account['institution']].join('/')
  FileUtils.mkdir_p(full_directory)

  [full_directory, "#{account_name}.#{extension}"].join('/')
end

def perform_request(path, token)
  url = "https://api.teller.io#{path}"
  JSON.parse(RestClient.get(url, {:Authorization => "Bearer #{token}"}))
end

def transactions(token, account)
  perform_request("/accounts/#{account['id']}/transactions", token)
end

def accounts(token)
  perform_request("/accounts", token)
end
