require 'openssl'
require 'zlib'

class BufLenInvalid < StandardError; end
class HmacInvalid < StandardError; end
class PackageInvalid < StandardError; end
class PackageTimeout < StandardError; end
class PackageCrcInvalid < StandardError; end

module Shadowsocks
  class Package
    attr_accessor :data
    attr_reader :password

    def initialize(options = {})
      @password = options.fetch(:password)
    end

    def push(buf)
      @store = '' if @store.nil?
      @store += buf
    end

    def pop
      len = bytes_to_i(@store[0..3])
      if len.nil?
        []
      else
        r = []

        while !@store.nil? && !len.nil? && @store.length >= len + 4
          r.push(@store[0..3+len])

          @store = @store[4+len..-1]
          len    = bytes_to_i(@store[0..3]) unless @store.nil?
        end
        r
      end
    end

    def pack_timestamp_and_crc(buf)
      buf_len   = i_to_bytes(buf.length)
      timestamp = i_to_bytes(Time.now.to_i)
      crc       = i_to_bytes(Zlib.crc32(timestamp + buf))

      buf_len + buf + timestamp + crc
    end

    def pack_hmac(buf)
      digest   = OpenSSL::Digest.new('sha1')
      hmac     = OpenSSL::HMAC.hexdigest(digest, password, buf)
      hmac_len = i_to_bytes(hmac.length)

      buf_len  = i_to_bytes(buf.length)
      data     = buf_len + buf + hmac_len + hmac

      i_to_bytes(data.length) + data
    end

    def unpack_timestamp_and_crc(buf)
      buf_len   = bytes_to_i(buf[0..3])
      real_buf  = buf[4..3+buf_len]

      timestamp = buf[4+buf_len..7+buf_len]
      crc32     = bytes_to_i(buf[8+buf_len..-1])

      raise PackageCrcInvalid if Zlib.crc32(timestamp + real_buf) != crc32
      raise PackageTimeout if Time.at(bytes_to_i(timestamp)) < (Time.now - 60)

      real_buf
    end

    # package length + buf length + buf + hmac length + hmac
    def unpack_hmac(buf)
      package_len = bytes_to_i(buf[0..3])

      raise BufLenInvalid if package_len != buf[4..-1].length

      buf_len  = bytes_to_i(buf[4..7])
      real_buf = buf[8..8 + buf_len - 1]

      hmac_len = bytes_to_i(buf[8 + buf_len..11+buf_len])
      hmac     = buf[12 + buf_len..-1]

      raise PackageInvalid if hmac_len != hmac.length

      digest        = OpenSSL::Digest.new('sha1')
      real_buf_hmac = OpenSSL::HMAC.hexdigest(digest, password, real_buf)

      raise HmacInvalid if real_buf_hmac != hmac

      real_buf
    end

    private

    def i_to_bytes(i)
      [i].pack('N')
    end

    def bytes_to_i(bytes)
      bytes.unpack('N')[0]
    end
  end
end
