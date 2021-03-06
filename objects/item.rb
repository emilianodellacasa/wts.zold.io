# Copyright (c) 2018 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'zold/key'
require 'zold/id'
require 'zold/log'
require_relative 'keygap'

#
# Item in AWS DynamoDB.
#
class Item
  def initialize(login, aws, log: Zold::Log::Quiet.new)
    raise 'Login can\'t be nil' if login.nil?
    @login = login.downcase
    raise 'AWS can\'t be nil' if aws.nil?
    @aws = aws
    raise 'Log can\'t be nil' if log.nil?
    @log = log
  end

  def exists?
    !items.empty?
  end

  # Creates a record in DynamoDB and generates a unique keygap.
  # +id+:: Wallet iD
  # +key+:: Private RSA key
  # +length+:: Length of keygap to use (don't change it without a necessity)
  def create(id, key, length: 8)
    raise 'ID can\'t be nil' if id.nil?
    raise 'Key can\'t be nil' if key.nil?
    raise 'Length can\'t be nil' if length.nil?
    pem, keygap = Keygap.new.extract(key.to_s, length)
    @aws.put_item(
      table_name: 'zold-wallets',
      item: {
        'login' => @login,
        'id' => id.to_s,
        'pem' => pem,
        'keygap' => keygap
      }
    )
    @log.info("New user @#{@login} created, wallet ID is #{id}, \
keygap is '#{keygap[0, 2]}#{'.' * (keygap.length - 2)}'")
    keygap
  end

  # Return private key as Zold::Key
  def key(keygap)
    raise "Keygap can\'t be nil for @#{@login}" if keygap.nil?
    key = read['pem']
    raise "There is no key for some reason for user @#{@login}" if key.nil?
    key = Keygap.new.merge(key, keygap)
    @log.debug("The private key of @#{@login} reassembled: #{key.to_s.length} chars")
    key
  end

  # Return private key as text
  def raw_key
    key = read['pem']
    raise "There is no key for some reason for user @#{@login}" if key.nil?
    key
  end

  # Return Wallet ID as Zold::Id
  def id
    id = Zold::Id.new(read['id'])
    @log.debug("The ID of @#{@login} retrieved: #{id}")
    id
  end

  def keygap
    keygap = read['keygap']
    raise "The user @#{@login} doesn't have a keygap anymore" if keygap.nil?
    @log.debug("The keygap of @#{@login} retrieved")
    keygap
  end

  # Returns TRUE if the keygap is absent in the item
  def wiped?
    read['keygap'].nil?
  end

  # Remove the keygap from DynamoDB
  def wipe(keygap)
    raise "Keygap can\'t be nil for @#{@login}" if keygap.nil?
    item = read
    if keygap != item['keygap']
      raise "Keygap '#{keygap}' of @#{@login} doesn't match \
'#{item['keygap'][0, 2]}#{'.' * (item['keygap'].length - 2)}'"
    end
    @aws.put_item(
      table_name: 'zold-wallets',
      item: {
        'login' => @login,
        'id' => item['id'],
        'pem' => item['pem']
      }
    )
    @log.debug("The keygap of @#{@login} was destroyed")
  end

  private

  def read
    item = items[0]
    raise "There is no item in DynamoDB for @#{@login}" if item.nil?
    item
  end

  def items
    @aws.query(
      table_name: 'zold-wallets',
      limit: 1,
      select: 'ALL_ATTRIBUTES',
      expression_attribute_values: { ':u' => @login },
      key_condition_expression: 'login=:u'
    ).items
  end
end
