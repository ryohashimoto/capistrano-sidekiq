git_plugin = self

namespace :sidekiq do
  desc 'Quiet sidekiq (stop fetching new tasks from Redis)'
  task :quiet do
    on roles fetch(:sidekiq_roles) do |role|
      git_plugin.switch_user(role) do
        execute :systemctl, "--user", "reload", fetch(:sidekiq_service_unit_name), raise_on_non_zero_exit: false
      end
    end
  end

  desc 'Stop sidekiq (graceful shutdown within timeout, put unfinished tasks back to Redis)'
  task :stop do
    on roles fetch(:sidekiq_roles) do |role|
      git_plugin.switch_user(role) do
        execute :systemctl, "--user", "stop", fetch(:sidekiq_service_unit_name)
      end
    end
  end

  desc 'Start sidekiq'
  task :start do
    on roles fetch(:sidekiq_roles) do |role|
      git_plugin.switch_user(role) do
        execute :systemctl, '--user', 'start', fetch(:sidekiq_service_unit_name)
      end
    end
  end

  desc 'Install systemd sidekiq service'
  task :install do
    on roles fetch(:sidekiq_roles) do |role|
      git_plugin.switch_user(role) do
        git_plugin.create_systemd_template
        execute :systemctl, "--user", "enable", fetch(:sidekiq_service_unit_name)
      end
    end
  end

  desc 'UnInstall systemd sidekiq service'
  task :uninstall do
    on roles fetch(:sidekiq_roles) do |role|
      git_plugin.switch_user(role) do
        execute :systemctl, "--user", "disable", fetch(:sidekiq_service_unit_name)
        execute :rm, File.join(fetch(:service_unit_path, fetch_systemd_unit_path), fetch(:sidekiq_service_unit_name))
      end
    end
  end

  def fetch_systemd_unit_path
    home_dir = backend.capture :pwd
    File.join(home_dir, ".config", "systemd", "user")
  end

  def create_systemd_template
    search_paths = [
        File.expand_path(
            File.join(*%w[.. .. .. generators capistrano sidekiq systemd templates sidekiq.service.capistrano.erb]),
            __FILE__
        ),
    ]
    template_path = search_paths.detect { |path| File.file?(path) }
    template = File.read(template_path)
    systemd_path = fetch(:service_unit_path, fetch_systemd_unit_path)
    backend.execute :mkdir, "-p", systemd_path
    backend.upload!(
        StringIO.new(ERB.new(template).result(binding)),
        "#{systemd_path}/#{fetch :sidekiq_service_unit_name}.service"
    )
    backend.execute :systemctl, "--user", "daemon-reload"
  end

  def switch_user(role)
    su_user = sidekiq_user(role)
    if su_user == role.user
      yield
    else
      as su_user do
        yield
      end
    end
  end

  def sidekiq_user(role)
    properties = role.properties
    properties.fetch(:sidekiq_user) || # local property for sidekiq only
        fetch(:sidekiq_user) ||
        properties.fetch(:run_as) || # global property across multiple capistrano gems
        role.user
  end
end
