# Author::    Anuj Luthra <anuj.luthra@gmail.com>
# Copyright:: Copyright (c) 2007 Anuj Luthra
# License::   Distributes under the same terms as Ruby

require 'socket'
module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class DialectGateway < Gateway 
      HOST       = 'localhost'
      PORT     = 9050
      QSI_RESPONSE_CODE_MESSAGES = {
        '0' => "Transaction Successful",
        '1' => "Transaction Declined",
        '2' => "Bank Declined Transaction",
        '3' => "No Reply from Bank",
        '4' => "Expired Card",
        '5' => "Insufficient Funds",
        '6' => "Error Communicating with Bank",
        '7' => "Payment Server detected an error",
        '8' => "Transaction Type Not Supported",
        '9' => "Bank declined transaction (Do not contact Bank)",
        'A' => "Transaction Aborted",
        'B' => "Transaction Declined - Contact the Bank",
        'C' => "Transaction Cancelled",
        'D' => "Deferred transaction has been received and is awaiting processing",
        'F' => "3-D Secure Authentication failed",
        'I' => "Card Security Code verification failed",
        'L' => "Shopping Transaction Locked (Please try the transaction again later)",
        'N' => "Cardholder is not enrolled in Authentication scheme",
        'P' => "Transaction has been received by the Payment Adaptor and is being processed",
        'R' => "Transaction was not processed - Reached limit of retry attempts allowed",
        'S' => "Duplicate OrderInfo",
        'T' => "Address Verification Failed",
        'U' => "Card Security Code Failed",
        'V' => "Address Verification and Card Security Code Failed",
        '?' => "Transaction status is unknown"
      }
     
      OK = '1'

      attr_reader :no_error, 
        :message, 
        :socket, 
        :response,
        :options
      
      
      #this makes sure that the money is sent as cents.
      self.money_format = :cents
      self.default_currency = 'AUD'
      self.supported_countries = ['AU']
      self.supported_cardtypes = [:visa, :master, :american_express, :diners_club]
      
      def initialize(options)  
        requires!(options, :merchant_id, :host, :port)
        @response = {}
        @no_error = true
        @socket = hello(options[:host],options[:port])
        @options = options
        super
      end
    	
      def purchase(money, creditcard, options = {})
        requires!(options, :invoice, :order_id)
        exp_date_str = "#{creditcard.year.to_s.last(2)}#{sprintf('%02d',creditcard.month)}"
        add_payment_info('CardNum'         , creditcard.number) if no_error
        add_payment_info('CardExp'         , exp_date_str)  if no_error
        add_payment_info('CardSecurityCode', creditcard.verification_value )  if no_error
        add_payment_info('MerchTxnRef'     , options[:order_id])  if no_error
        add_payment_info('TicketNo'        , options[:invoice])  if no_error       
        
        #submit the payment to payment client
        post_payment(options[:order_details], @options[:merchant_id], amount(money),'en')  if no_error
        build_transaction_info if no_error
        bye
        success = (@message == QSI_RESPONSE_CODE_MESSAGES['0'])
        Response.new(success, @message, @response,
          :authorization => response["DigitalReceipt.TransactionNo"]) 
      end
    
      def self.supported_cardtypes
        [:visa, :master]
      end
    
      private 
      
      def hello(host,port)
        begin
          @socket = TCPSocket.new(host,port)
        rescue Errno::ETIMEDOUT
          @message = " Timed out (#{@host}:#{@port})"
          @no_error = false
        rescue SocketError => e
          @message = " Socket error - #{e}"
          @no_error = false
        rescue Exception => e
          @message = " Error happened while connecting to payment gateway - #{e}"
          @no_error = false
        end
      end
            
      def bye
        socket.close if socket
      end
         
      #adds information which is required to build a digital order
      def add_payment_info(key, value)        
        dispatch('7', key, value)        
        @message = "Failed to add Payment data : #{key} : #{value}" unless @no_error
      end 
      
      #sends the digital order.
      def post_payment(order_details, merchant_id, amount, locale='en')
        dispatch('6',order_details, merchant_id, amount, locale)        
        @message = get_payment_client_error('PaymentClient.Error') unless @no_error
      end

      #gathers the information regarding the submitted digital order.
      def build_transaction_info
        if info_available?
          @message = qsi_response
          all_keys.each do |key|
            key.chomp!
            @response[key] = digital_reciept_info(key)
          end          
        end
      end
      
      #if any information is avaialble for the submission of digital order
      def info_available?
        dispatch('5')
        answer = @no_error
        @message = get_payment_client_error('PaymentClient.Error') unless @no_error
        answer
      end
      
      #gets the description for the returned response code. (result of transaction)
      def qsi_response
        code = digital_reciept_info('DigitalReceipt.QSIResponseCode')
        return @no_error ? QSI_RESPONSE_CODE_MESSAGES[code.chomp!] : code
      end

      def digital_reciept_info(key)
        value = dispatch('4', key).split(',')[1]
        if @no_error
          return value
        else
          return "No result for this field : #{key}"
        end
      end
      
      #get all the information fields available in response to digital order submission
      def all_keys
        keys = dispatch('33').split(',')
        #the reponse is "1,field1,field2,...." where 1 is success and rest are avail feilds.
        keys = keys[1..(keys.length)]
      end
      
      #get the error messages.
      def get_payment_client_error(error_type)
        answer = dispatch('4',error_type).split(',')[1]
      end
      
      #send the message to the payment client and recieve the answer.
      def dispatch(message_id, *fields)        
        formatted_message = ([message_id] + fields).join(',').to_str
        socket.send("#{formatted_message}\n",0)
        answer = socket.recv(500)        
        @no_error = ((answer.split',')[0] == OK) ? true:false     
        answer
      end 

    end
  end
end
