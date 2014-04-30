require 'rubygems'
require 'net/http'
require 'uri'
require 'openssl'
require 'nokogiri'

class EC2InstanceTypeMatrix
  def initialize
    uri = URI.parse('https://aws.amazon.com/amazon-linux-ami/instance-type-matrix/')
    http = Net::HTTP.new(uri.host, uri.port)
    if uri.scheme == 'https'
      http.use_ssl = true
      # TODOLATER - http://www.rubyinside.com/how-to-cure-nethttps-risky-default-https-behavior-4010.html
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    # HTTP response data.
    use_data = response.body.chomp

    # Grab the html table out that contains the Instance Type Matrix.
    start_string = '<table width="100%" cellspacing="0" cellpadding="1" border="0" jcr:primarytype="nt:unstructured">'
    end_string = '</tr></tbody></table>'
    instance_type_matrix_html = use_data[/#{start_string}(.*?)#{end_string}/m, 1]
    # Put a table around this to make it valid HTML again.
    instance_type_matrix_html = "<table>#{instance_type_matrix_html}</tr></tbody></table>"

    @instance_type_matrix_result = Hash.new
    instance_type_matrix_columns = Hash.new
    instance_type_matrix = Nokogiri::HTML.fragment(instance_type_matrix_html)
    instance_type_matrix.search('tr').each do |tr|
      first_td_children_b = tr.first_element_child.children.search('b')
      if first_td_children_b.length == 1
        # Header Row.
        if first_td_children_b.text == 'Instance Type'
          header_td_skip_first = false
          header_td_iterator = 0
          tr.search('td').each do |header_td|
            if header_td_skip_first == false
              header_td_skip_first = true
              # Skip 'Instance Type'
              next
            end
            this_td_text = header_td.text.split("\n").join.chomp
            translate_this_td_text = this_td_text.downcase.gsub(/-backed/, '').gsub(/[\(\)]/, '').gsub(/ /, '_').gsub(/-bit/, 'bit')
            instance_type_matrix_columns[header_td_iterator] = translate_this_td_text.to_s
            header_td_iterator = header_td_iterator + 1
          end
        else
          raise 'Error - Malformed HTML received, this parser may no longer work on the page requested.'
        end
      else
        # Data Row.
        instance_type_handled = false
        this_instance_type = ''
        data_td_iterator = 0
        tr.search('td').each do |td|
          # First td is the Instance Type
          if instance_type_handled == false
            this_instance_type = td.text.chomp
            @instance_type_matrix_result[this_instance_type] = Hash.new
            instance_type_handled = true
            next
          end
          # Make sure we have a key name to use here.
          if ! instance_type_matrix_columns.has_key? data_td_iterator
            raise 'Error - Malformed HTML received, column mismatch in data row. This parser may no longer work on the page requested.'
          end
          # Check if a "tick" is set in the text of this td.
          if td.text == '✓'
            @instance_type_matrix_result[this_instance_type][instance_type_matrix_columns[data_td_iterator]] = true
          else
            @instance_type_matrix_result[this_instance_type][instance_type_matrix_columns[data_td_iterator]] = false
          end
          data_td_iterator = data_td_iterator + 1
        end
      end
    end
  end

  def query (instance_type)
    if ! @instance_type_matrix_result.has_key? instance_type
      raise 'Error - Could not find the Instance Type specified in our Matrix.'
    end
    return @instance_type_matrix_result[instance_type]
  end
end # Class
