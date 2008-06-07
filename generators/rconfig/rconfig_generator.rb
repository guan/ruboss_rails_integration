##########################################################################
# Copyright 2008, Ruboss Technology Corporation.
#
# This is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License v3 as
# published by the Free Software Foundation.
#
# This software is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License v3 for more details.
#
# You should have received a copy of the GNU General Public
# License v3 along with this software; if not, write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
# 02110-1301 USA, or see the FSF site: http://www.fsf.org.
##########################################################################
class RconfigGenerator < Rails::Generator::Base
  include Ruboss::Configuration 
  
  attr_reader :project_name, 
              :flex_project_name, 
              :base_package, 
              :base_folder, 
              :command_controller_name, 
              :component_names, 
              :application_tag, 
              :air_config

  def initialize(runtime_args, runtime_options = {})
    super
    @project_name, @flex_project_name, @command_controller_name, @base_package, @base_folder = extract_names

    @main_app_only = options[:target] == :main_app_only
    
    # if we updating main file only we probably want to maintain the type of project it is
    if @main_app_only
      project_file_name = ::RAILS_ROOT + '/.project'
      if (File.exist?(project_file_name) && 
        File.read(project_file_name) =~ /com.adobe.flexbuilder.apollo.apollobuilder/m)
        @air_config = true
      end
    else
      @air_config = @args.first == 'air'
    end
    
    if @air_config
      @application_tag = 'WindowedApplication'
    else
      @application_tag = 'Application'
    end
    
    @component_names = []
    if File.exists?("app/flex/#{base_folder}/components/generated")
      @component_names = list_mxml_files("app/flex/#{base_folder}/components/generated")
    end
  end

  def manifest
    record do |m|
      if !@main_app_only
        m.file 'flex.properties', '.flexProperties'
        if @air_config
          m.template 'actionscriptair.properties', '.actionScriptProperties'
          m.template 'projectair.properties', '.project'
        else
          m.template 'actionscript.properties', '.actionScriptProperties'
          m.template 'project.properties', '.project'
        end
  
        m.directory 'html-template/history'      
        %w(index.template.html AC_OETags.js playerProductInstall.swf).each do |file|
          m.file "html-template/#{file}", "html-template/#{file}"
        end
        
        %w(history.css history.js historyFrame.html).each do |file|
          m.file "html-template/history/#{file}", "html-template/history/#{file}"
        end
        
        %w(components controllers commands models events).each do |dir|
          m.directory "app/flex/#{base_folder}/#{dir}"
        end
        
        m.directory "app/flex/#{base_folder}/components/generated"
  
        m.file 'swfobject.js', 'public/javascripts/swfobject.js'
        m.file 'expressInstall.swf', 'public/expressInstall.swf'
        m.template 'index.html.erb', 'public/index.html'
        
        m.dependency 'rcontroller', @args
      end
      m.template 'mainapp.mxml', File.join('app/flex', "#{project_name}.mxml")
      m.template 'mainair-app.xml', File.join('app/flex', "#{project_name}-app.xml") if @air_config
    end
  end

  protected
    def banner
      "Usage: #{$0} #{spec.name}" 
    end
end