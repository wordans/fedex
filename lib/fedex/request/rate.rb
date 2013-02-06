require 'fedex/request/base'

module Fedex
  module Request
    class Rate < Base

      def initialize(credentials, options={})
        super
        @saturday_rates = options[:saturday_rates]
        @future_day = options[:future_day]
      end

      # Sends post request to Fedex web service and parse the response, a Rate object is created if the response is successful
      def process_request

        api_response = self.class.post(api_url, :body => build_xml)
        puts api_response if @debug
        response = parse_response(api_response)

        if success?(response)
          rate_details = [response[:rate_reply][:rate_reply_details][:rated_shipment_details]].flatten.first[:shipment_rate_detail]
          Fedex::Rate.new(rate_details)
        else
          error_message = if response[:rate_reply]
            [response[:rate_reply][:notifications]].flatten.first[:message]
          else
            "#{api_response["Fault"]["detail"]["fault"]["reason"]}\n#{api_response["Fault"]["detail"]["fault"]["details"]["ValidationFailureDetail"]["message"]}"
          end rescue $1
          return error_message
        end
      end

      private

      # Add information for shipments
      def add_requested_shipment(xml)

        xml.RequestedShipment{

          xml.ShipTimestamp (Time.now + @future_day.days).utc.iso8601(2)
          xml.DropoffType @shipping_options[:drop_off_type] ||= "REGULAR_PICKUP"
          xml.ServiceType service_type
          xml.PackagingType @shipping_options[:packaging_type] ||= "YOUR_PACKAGING"
          add_shipper(xml)
          add_recipient(xml)
          add_shipping_charges_payment(xml)
          add_saturday_option(xml) if @saturday_rates
          add_customs_clearance(xml) if @customs_clearance

          if @saturday_rates
            xml.RateRequestTypes "LIST"
          else
            xml.RateRequestTypes "ACCOUNT"
          end

          add_packages(xml)
        }
      end

      def add_shipping_charges_payment(xml)

        xml.ShippingChargesPayment {

          xml.PaymentType "SENDER"
          xml.Payor { xml.ResponsibleParty { xml.AccountNumber @credentials.account_number } }
        }
      end

      def add_saturday_option(xml)

        xml.SpecialServicesRequested { xml.SpecialServiceTypes "SATURDAY_DELIVERY" }
      end

      # Build xml Fedex Web Service request
      def build_xml
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.RateRequest(:xmlns => "http://fedex.com/ws/rate/v13"){
            add_web_authentication_detail(xml)
            add_client_detail(xml)
            add_version(xml)
            xml.ReturnTransitAndCommit true if @saturday_rates
            add_requested_shipment(xml)
          }
        end
        builder.doc.root.to_xml
      end

      def service
        { :id => 'crs', :version => 13 }
      end

      # Successful request
      def success?(response)
        response[:rate_reply] &&
          %w{SUCCESS WARNING NOTE}.include?(response[:rate_reply][:highest_severity])
      end
    end
  end
end
