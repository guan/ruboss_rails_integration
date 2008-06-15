require 'rake'
require 'ftools'
require 'rexml/document'

namespace :db do
  namespace :mysql do
    namespace :stage do
      desc "Stage production, test and development databases"
      task :all => :environment do
        db_names = %w(development test production)
        admin_password = ENV["ADMINPASS"] || ""
        db_user_name = ENV["USER"] || "root"
        db_password = ENV["PASS"] || ""
        stage_database(db_names, admin_password, db_user_name, db_password)
      end
    end

    desc "Stage the database environment for #{RAILS_ENV}"    
    task :stage => :environment do
      db_names = [::RAILS_ENV]
      admin_password = ENV["ADMINPASS"] || ""
      db_user_name = ENV["USER"] || "root"
      db_password = ENV["PASS"] || ""
      stage_database(db_names, admin_password, db_user_name, db_password)
    end
  end  
    
  def stage_database(db_names, admin_password, db_user_name, db_password)
    sql_command = ""
    
    db_names.each do |name|
      db_name = ActiveRecord::Base.configurations[name]['database']
      sql_command += "drop database if exists #{db_name}; " << 
        "create database #{db_name}; grant all privileges on #{db_name}.* " << 
        "to #{db_user_name}@localhost identified by \'#{db_password}\';"
      ActiveRecord::Base.configurations[name]['username'] = db_user_name
      ActiveRecord::Base.configurations[name]['password'] = db_password
    end

    if (!File.exist?("#{RAILS_ROOT}/tmp/stage.sql"))
      File.open("#{RAILS_ROOT}/tmp/stage.sql", "w") do |file|
        file.print sql_command
      end
    end

    # back up the original database.yml file just in case
    File.copy("#{RAILS_ROOT}/config/database.yml", 
      "#{RAILS_ROOT}/config/database.yml.sample") if !File.exist?("#{RAILS_ROOT}/config/database.yml.sample")
    
    dbconfig = File.read("#{RAILS_ROOT}/config/database.yml")
    dbconfig.gsub!(/username:.*/, "username: #{db_user_name}")
    dbconfig.gsub!(/password:.*/, "password: #{db_password}")
    
    File.open("#{RAILS_ROOT}/config/database.yml", "w") do |file|
      file.print dbconfig
    end

    if system %(mysql -h localhost -u root --password=#{admin_password} < tmp/stage.sql)
      puts "Updated config/database.yml and staged the database based on your settings"
      File.delete("tmp/stage.sql") if File.file?("tmp/stage.sql")
    else
      puts "Staging was not performed. Check console for errors. It is possible that 'mysql' executable was not found."
    end
  end
  
  desc "Drop the database environment for #{RAILS_ENV} only if it exists"
  task :drop_if_exists => :environment do
    Rake::Task["db:drop"].invoke rescue nil
  end
    
  desc "Refresh the database environment for #{RAILS_ENV}"
  task :refresh => ['db:drop_if_exists', 'db:create', 'db:migrate', 'db:fixtures:load']
end

namespace :ruboss do
  def compile_app(executable, destination)
    app_properties = REXML::Document.new(File.open(File.join(RAILS_ROOT, ".actionScriptProperties")))
    app_properties.elements.each("*/applications/application") do |elm|
      app_path = elm.attributes['path']
      project_path = File.join(RAILS_ROOT, "app/flex", app_path)
      target_project_path = project_path.sub(/.mxml$/, '.swf')
      target_project_air_descriptor = project_path.sub(/.mxml$/, '-app.xml')
      
      libs = Dir.glob(File.join(RAILS_ROOT, 'lib', '*.swc'))
      
      cmd = "#{executable} -library-path+=#{libs.join(',')} " << 
        "-keep-as3-metadata+=Resource,HasMany,HasOne,BelongsTo,DateTime,Lazy,Ignored #{project_path}"
      puts "Compiling #{project_path}"
      if system(cmd)
        FileUtils.makedirs File.join(RAILS_ROOT, destination)
        puts "Moving #{target_project_path} to " + File.join(RAILS_ROOT, destination)
        FileUtils.mv target_project_path, File.join(RAILS_ROOT, destination), :force => true
        if File.exist?(target_project_air_descriptor)
          descriptor = File.read(target_project_air_descriptor)
          descriptor_name = target_project_air_descriptor.split("/").last
          app_swf = target_project_path.split("/").last
          descriptor.gsub!("[This value will be overwritten by Flex Builder in the output app.xml]", 
            app_swf)

          File.open("#{RAILS_ROOT}/#{destination}/#{descriptor_name}", "w") do |file|
            file.print descriptor
          end
          puts "Created #{RAILS_ROOT}/#{destination}/#{descriptor_name} descriptor."
        end
        puts 'Done!'
      else
        puts "The application was not compiled. Check console for errors. " <<
          "It is possible that '(a)mxmlc' executable was not found or there are compilation errors."
      end
    end    
  end
  
  def get_main_application
    app_properties = REXML::Document.new(File.open(File.join(RAILS_ROOT, ".actionScriptProperties")))
    app_properties.root.attributes['mainApplicationPath'].split("/").last
  end
  
  namespace :flex do
    desc "Build project swf file and move it into public/bin folder"
    task :build => [:environment] do
      compile_app('mxmlc', 'public/bin')
    end
  end
  
  namespace :air do
    desc "Build project swf file as an AIR application and move it into bin-debug folder"
    task :build => [:environment] do
      compile_app('amxmlc', 'bin-debug')
    end
    
    desc "Run the AIR application (if this project is configured as an AIR project)"
    task :run => [:environment] do
      target = get_main_application.gsub(/.mxml$/, '-app.xml')
      puts "Running AIR application with descriptor: #{target}"
      if !system("adl bin-debug/#{target}")
        puts "Could not run the application with descriptor: #{target}. Check console for errors."
      end
    end
  end
  
  namespace :migrate do
    desc "Adds a 'format.fxml ...' line for each 'format.xml ...' line in every controller"
    task :controllers => [:environment] do
      @controllers = Dir.glob(File.join(RAILS_ROOT, 'app', 'controllers', '*_controller.rb'))
      @controllers.each do |controller|
        already_migrated = false
        new_lines = File.open(controller, 'r').readlines.collect do |line|
          (already_migrated = true ; next ) if line =~ /fxml/ # don't re-migrate a controller that already contains .fxml
          instance_name = File.basename(controller, '.rb').gsub(/_controller/, '').singularize
          if line =~ /^\s+format\.xml/
            if line =~ /head :ok/
              fxml_line = line.gsub(/head :ok/, "render :xml => @#{instance_name}")
            else
              fxml_line = line.gsub(/format\.xml/, 'format.fxml')
              fxml_line.gsub!(/, :status[^\}]+/, ' ')
            end
            [line, fxml_line]
          else
            line
          end
        end.flatten
        unless already_migrated  
          file = File.open(controller, 'w') do |file|
            file.puts new_lines
          end
        end
      end
    end
  end
end