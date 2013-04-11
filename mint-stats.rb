require 'csv'
require 'date'
require 'yaml'
require 'data_mapper'
require 'dm-ar-finders'
require 'dm-aggregates'
require 'active_support/all'
require "uri"
require "mechanize"

hostname = "https://wwws.mint.com/"

unless ARGV.length == 2
  puts "Usage: ruby #{$0} USERNAME PASSWORD"
  exit 1
end

username = ARGV[0]
password = ARGV[1]

agent = Mechanize.new
agent.pluggable_parser.default = Mechanize::Download

page  = agent.get(URI.join hostname, "/login.event")
form = page.form_with(:id => "form-login")

form.username = username
form.password = password
form.submit

TRANSACTIONS_CSV = agent.get(URI.join hostname, "/transactionDownload.event").body

START_DATE = Date.today - 30
END_DATE = Date.today

begin # define ActiveRecord objects

  class Transaction
  	include DataMapper::Resource

    belongs_to :transaction_type
    has 1, :category
    has 1, :account

  	property :id, Serial
    property :name, Text
    property :date, Date
    property :description, Text
    property :original_description, Text
    property :labels, Text
    property :notes, Text
    property :amount, Float
  end

  class TransactionType
  	include DataMapper::Resource

    has n, :transactions

  	property :id, Serial
    property :name, Text
  end

  class Category
  	include DataMapper::Resource

  	property :id, Serial
    property :name, Text
  end

  class Account
  	include DataMapper::Resource

  	property :id, Serial
    property :name, Text
  end

  DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite::memory:")

  DataMapper.finalize
  DataMapper.auto_upgrade!
end

def dateobj string
  Date.strptime(string, "%m/%d/%Y").strftime("%d-%m-%Y")
end

def create_database_from_csv
  CSV.parse(TRANSACTIONS_CSV, headers: true) do |row|
    x = row.to_hash
    x['Date'] = dateobj(x['Date'])
    x['Amount'] = x['Amount'].to_i
    if Date.parse(x['Date']) > START_DATE && x['Category'] != 'Exclude From Mint'
      Transaction.create! date: x['Date'],
        description: x['Description'],
        original_description: x['Original Description'],
        amount: x['Amount'],
        transaction_type: TransactionType.first_or_create(:name => x['Transaction Type']),
        category: Category.first_or_create(:name => x['Category']),
        account: Account.first_or_create(:name => x['Account Name']),
        labels: x['Labels'],
        notes: x['Notes']
      end
  end
end

create_database_from_csv

output = [["Date", "Spending"]]
CSV.open("output.csv", "wb") do |csv|
  (START_DATE..END_DATE).each do |day|
    debit = TransactionType.first(:name => 'debit')
    csv << [day.strftime("%m/%d/%Y"), Transaction.sum(:amount, :date => day, :transaction_type => debit)]
  end
end
