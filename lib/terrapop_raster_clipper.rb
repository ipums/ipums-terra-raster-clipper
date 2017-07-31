# Copyright (c) 2012-2017 Regents of the University of Minnesota
#
# This file is part of the Minnesota Population Center's IPUMS Terra Project.
# For copyright and licensing information, see the NOTICE and LICENSE files
# in this project's top-level directory, and also on-line at:
#   https://github.com/mnpopcenter/ipums-terra-raster-clipper

require "terrapop_raster_clipper/engine"


module TerrapopRasterClipper
  class Clipper
    def initialize(request)
      @request = request
      @raster_year = request[:year]
      @band = request[:band]
      @output_type = request[:output_type]
      @raster_variable_mnemonic = request[:raster_variable_mnemonic]
      @country_mnemonic = request[:country_mnemonic]
      @origin = request[:origin]
      @path = request[:path]
      @sql_index = 0
      @is_cruts = request[:is_cruts].nil? ? false : request[:is_cruts]
      @tmp_path_cruts = request[:tmp_path_cruts].nil? ? nil : request[:tmp_path_cruts]
      
      if @is_cruts
        @sql_index = 1
      end
      
    end

    def file_path
      @path.nil? ? File.join(Rails.root.to_s, 'public', 'raster_cache', filename) : (@path + filename)
    end

    def mime_type
      ['tiff', 'tif'].include?(@output_type) ? "image/tiff" : "image/png"
    end

    def create_extract_request(remote_ip)
      extract_request = ExtractRequest.new()
      extract_request.raster_variables << @raster_variable
      extract_request.raster_datasets << @raster_dataset
      extract_request.sample_geog_levels << @sample_geog_level
      extract_request.raster_only = true
      extract_request.file_type = @output_type
      extract_request.origin = @origin
      extract_request.user_ip_address = remote_ip
      extract_request.save(validate: false)
      extract_request.completed
    end

    def clip
      (@output_type.nil? || @raster_variable_mnemonic.nil? || @country_mnemonic.nil?) && (raise ClippingError.new("Incorrect Clipping Parameters"))
      @raster_variable = RasterVariable.find_by!(mnemonic: @raster_variable_mnemonic.upcase)
      
      unless @is_cruts
        @raster_dataset = @raster_year.nil? ? @raster_variable.raster_datasets.first : @raster_variable.raster_datasets.where(["begin_year = ? or end_year = ?", @raster_year.to_i, @raster_year.to_i]).first
        @raster_dataset.nil? && (raise ClippingError.new("Nil RasterDataset for #{@raster_variable.inspect}"))
      end
      
      #if @is_cruts
        # we need to move the image from the temp directory on the db server to a location that we can get to from the extract server
        #unless File.exist? @tmp_path_cruts
        #  FileUtils.mkdir_p @tmp_path_cruts
        #end
      #end
            
      country = Country.find_by!(short_name: @country_mnemonic.downcase)
      country.all_country_years_and_ranked_geography(false, false).each do |country_year_and_geography|
        @countryyear = country_year_and_geography[:countryyear]
        @sample_geog_level = country_year_and_geography[:sample_geog_level]
        @sample_geog_level.nil? && (raise ClippingError.new("Unable to locate a geographic level object for requested country ['#{country.full_name}'] and specified year ['#{year}']"))
        #binding.pry
        
        prepare_sql()
        prepare_raster_directory(File.dirname(file_path))

        #File.exist?(file_path) ? return : success = prepare_file(file_path)
        success = prepare_file(file_path)
        success ? return : (raise ClippingError.new("Unable to clip raster"))
      end
    end

    private

    def prepare_sql
      @sql = ["SELECT terrapop_raster_to_image_v3(#{@sample_geog_level.id}, #{@raster_variable.id}, #{@band}) AS geotiff",
              "SELECT (terrapop_netcdf_to_image( #{@sample_geog_level.id}, #{@raster_variable.id}, '#{@raster_year}', '#{@tmp_path_cruts}'))"]
    end


    def filename
      "#{@raster_variable_mnemonic.upcase}#{@raster_year}#{@countryyear}#{['tiff', 'tif'].include?(@output_type) ? ".tiff" : ".png"}"
    end


    def file_prefix
      "#{@raster_variable.mnemonic}#{@raster_year}#{@countryyear}"
    end


    def prepare_raster_directory(dir)
      unless File.exist?(dir)
        FileUtils.mkdir_p dir
        FileUtils.chmod 0777, dir
      end
    end


    def prepare_file(file_path)
      #Rails.logger.info "*** File [#{file_path}] does not exist ***"
      errors = []
      results = nil
            
      begin 
        sql = @sql[@sql_index]
        
        $stderr.puts "#{__FILE__}:#{__LINE__}: #{sql}"
        
        results = ActiveRecord::Base.connection.execute(sql)
        
        if @is_cruts
          rs = []
        
          #binding.pry
        
          #  nodata_value | srid | final_image | image_path | data_type 
          results.each do |row|
            nodata_value, srid, final_image, image_path, data_type = row.first.second.to_s.split(/,/)
            r = {}
          
            r['nodata_value'] = nodata_value.gsub('(', '')
            r['srid']         = srid
            r['final_image']  = final_image
            r['image_path']   = image_path
            r['data_type']    = data_type.gsub(')', '')
          
            rs << r
          
          end
        
          results = rs
        end
        
      rescue Exception => e
        errors << e
        raise ClippingError.new("#{e.message}")
      end

      if results.nil?
        Notifier.email_stacktraces("Failed to clip raster with '#{@sample_geog_level.inspect}'\n\n", errors).deliver
        return false
      end
      
      #binding.pry
      
      if @is_cruts
        transformed_results = []
        
        results.each_with_index do |r,idx|
          if r['data_type'] == 'data'
            
            sql = "SELECT readfile_as_base64('#{r['image_path']}') AS b64_geotiff"
                          
            actual_tiff = ActiveRecord::Base.connection.execute(sql)
            
            #binding.pry
            
            unless actual_tiff.nil?
              actual_tiff.each do |rr|
                transformed_results << {'geotiff' => Base64.decode64(rr['b64_geotiff']) }
              end
            end

          else
            $stderr.puts "===>> #{r}"
          end
        end
        
        results = transformed_results
        
      end

      #binding.pry

      #binding.pry
      
      prepare_raster_directory(File.dirname(file_path) + "/temp/" + "#{file_prefix}/")

      temp_dir = File.dirname(file_path) + "/temp/" + "#{file_prefix}/"
      paths_file_path = temp_dir + "#{file_prefix}.txt"
      vrt_file_path = temp_dir +  "output.vrt"

      #File.new(vrt_file_path, 'wb')
      all_files = ''

      results.each_with_index do |item, index|
        temp_file_path = temp_dir + "#{file_prefix}_#{index}"
        $stderr.puts temp_file_path
        all_files += temp_file_path + "\n"
        File.open(temp_file_path, 'wb') { |f| f.write item['geotiff'] }
      end


      File.open(paths_file_path, "wb") { |f| f.write(all_files) }

      #binding.pry
      
      puts `gdalbuildvrt -input_file_list #{paths_file_path} #{vrt_file_path}`

      #binding.pry
      
      $stderr.puts "#{__FILE__}:#{__LINE__} => #{file_path}"

      ['tiff', 'tif'].include?(@output_type) ? (puts `gdal_translate -of GTIFF #{vrt_file_path} #{file_path}`)
                                             : (puts `gdal_translate -of GTIFF #{vrt_file_path} #{temp_dir}/out.tiff`)
      
      puts `gdal_translate -ot Byte -of PNG #{temp_dir}/out.tiff #{file_path}` if @output_type == 'png'

      begin
        FileUtils.chown(nil, 'local_terrapopdeploy', "#{temp_dir}/*")
      rescue Exception => e
        $stderr.puts e
      end

      FileUtils.chmod 0777, file_path
      true
    end

  end

  class ClippingError < StandardError
    def initialize(msg="Something went wrong in clipping your raster")
      super(msg)
    end
  end

end
