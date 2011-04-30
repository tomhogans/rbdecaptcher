
# = Synopsis
# rbDecaptcher library accepts CAPTCHA images and processes them
# through the Decaptcher service. 
#
# == Example
#
#  d = Decaptcher.new
#  p d.solve File.new("image.jpeg", "r")
#  p d.solve_url "http://www.google.com/images/logos/logo.png"
# 

require 'net/http'
require 'uri'
require 'cgi'

class DecaptcherError < Exception
end

class ReCaptchaError < Exception
end

class Decaptcher
    VERSION = '1.0'
    CONNECTION_TIMEOUT = 10
    USER_AGENT = "Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 5.1; .NET CLR 1.1.4322; .NET CLR 2.0.50727)"
    BOUNDARY = "ThiS_CouLd__Be_AnYTHING"
    RECAPTCHA_CHALLENGE = "http://www.google.com/recaptcha/api/challenge?k="
    RECAPTCHA_IMAGE = "http://www.google.com/recaptcha/api/image?c="

    def initialize(username, password, timeout=120, api_url=nil)
        @username = username
        @password = password
        @timeout = timeout
        unless api_url
            @post_url = "http://poster.decaptcher.com/" 
        end
        @proxy_host = @proxy_port = @proxy_user = @proxy_pass = nil
    end

    def set_proxy(host, port, username=nil, password=nil)
        @proxy_host = host
        @proxy_port = port
        @proxy_user = username
        @proxy_pass = password
    end

    def solve(image_data)
        uri = URI.parse(@post_url)

        params = [
            text_to_multipart("function", "picture2"),
            text_to_multipart("username", @username),
            text_to_multipart("password", @password),
            text_to_multipart("pict_type", "0"),
            text_to_multipart("pict_to", "0"),
            file_to_multipart("pict", "image.jpeg", "image/jpeg", image_data)
        ]

        post_body = params.collect { |p| "--#{BOUNDARY}\r\n#{p}" }.join('') + "--#{BOUNDARY}--\r\n"

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = CONNECTION_TIMEOUT
        http.read_timeout = @timeout
        request = Net::HTTP::Post.new(uri.request_uri)
        request.body = post_body
        request["Content-Type"] = "multipart/form-data, boundary=#{BOUNDARY}"
        start_time = Time.now
        response = http.request(request)
        stop_time = Time.now
        results = response.body.split("|")
        if results.count != 6:
            case results.first
            when "-5"
                raise DecaptcherError, "Decaptcher service too busy"
            when "-6"
                raise DecaptcherError, "Decaptcher balance empty for user #{@username}"
            else
                raise DecaptcherError, "Decaptcher error #{results.first}"
            end
        else
            {
                "pic_id" => "#{results[1]}:#{results[2]}",
                "text" => results[5],
                "timing" => (stop_time - start_time)
            }
        end
    end

    def solve_url(image_url)
        uri = URI.parse(image_url)
        http = Net::HTTP::Proxy(@proxy_host, @proxy_port, @proxy_user, 
                                @proxy_pass).new(uri.host, uri.port)
        http.open_timeout = CONNECTION_TIMEOUT
        request = Net::HTTP::Get.new(uri.request_uri)
        request["User-Agent"] = USER_AGENT
        response = http.request(request)
        solve(response.body)
    end

    def solve_recaptcha(site_id)
        uri = URI.parse(RECAPTCHA_CHALLENGE + site_id)
        http = Net::HTTP::Proxy(@proxy_host, @proxy_port, @proxy_user, 
                                @proxy_pass).new(uri.host, uri.port)
        p @proxy_user, @proxy_pass
        http.open_timeout = CONNECTION_TIMEOUT
        request = Net::HTTP::Get.new(uri.request_uri)
        request["User-Agent"] = USER_AGENT
        response = http.request(request)

        begin
            challenge = /challenge\s+:\s+'(.*?)',/.match(response.body).captures.first
        rescue
            case response.code
            when 200
                raise ReCaptchaError, "No challenge code detected"
            else
                raise StandardError, "HTTP failed with code #{response.code}"
            end
        end

        solve_url(RECAPTCHA_IMAGE + challenge)
    end

    def req_refund(pic_id)
        id_list = pic_id.split(":")
        if id_list.count != 2
            raise ArgumentError, "pic_id must be in format major_id:minor_id"
        end
        
        uri = URI.parse(@post_url)
        response = Net::HTTP.post_form(uri, {
            "function" => "picture_bad2",
            "username" => @username,
            "password" => @password,
            "major_id" => id_list.first,
            "minor_id" => id_list.last
        })
        response.body
    end

    def get_balance
        uri = URI.parse(@post_url)
        response = Net::HTTP.post_form(uri, {
            "function" => "balance",
            "username" => @username,
            "password" => @password
        })
        response.body
    end

end


# Multipart post functions below taken from blog post at:
# http://realityforge.org/code/rails/2006/03/02/upload-a-file-via-post-with-net-http.html

def text_to_multipart(key, value)
    return "Content-Disposition: form-data; name=\"#{CGI::escape(key)}\"\r\n" +
        "\r\n" + 
        "#{value}\r\n"
end

def file_to_multipart(key, filename, mime_type, content)
    return "Content-Disposition: form-data; name=\"#{CGI::escape(key)}\"; filename=\"#{filename}\"\r\n" +
        "Content-Transfer-Encoding: binary\r\n" +
        "Content-Type: #{mime_type}\r\n" + 
        "\r\n" + 
        "#{content}\r\n"
end

