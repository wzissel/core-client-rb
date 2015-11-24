class Ey::Core::Client::Environment < Ey::Core::Model
  extend Ey::Core::Associations

  identity :id

  attribute :classic, type: :boolean
  attribute :name
  attribute :created_at, type: :time
  attribute :deleted_at, type: :time
  attribute :monitor_url
  attribute :region

  has_one :account
  has_one :database_service
  has_one :firewall

  has_many :costs
  has_many :keypairs
  has_many :servers
  has_many :applications
  has_many :logical_databases

  attr_accessor :application_id

  # @param application [Ey::Core::Client::Application]
  # @option opts [Ey::Core::Client::ApplicationArchive] :archive
  def deploy(application, opts={})
    raise "Environment does not contain an app deployment for this application" unless self.applications.get(application.id)
    raise ":ref is a required key" unless opts[:ref]
    connection.requests.new(connection.deploy_environment_application({"deploy" => opts}.merge("id" => self.id, "application_id" => application.id)).body["request"])
  end

  # @param application [Ey::Core::Client::Application]
  # @param action [String]
  # @option opts [Ey::Core::Client::ApplicationArchive] :archive
  def run_action(application, action, task={})
    requires :id

    response = self.connection.run_environment_application_action(
      "environment" => self.id,
      "application" => application.id,
      "task"        => task,
      "action"      => action,
    )
    connection.requests.new(response.body["request"])
  end

  def deprovision
    connection.requests.new(self.connection.deprovision_environment("id" => self.id).body["request"])
  end

  def destroy!
    connection.requests.new(self.connection.destroy_environment("id" => self.id).body["request"])
  end

  def application
    if self.application_id
      connection.applications.get(self.application_id)
    end
  end

  def boot(options={})
    options = Cistern::Hash.stringify_keys(options)
    raise "configuration is a required key" unless options["configuration"]
    raise "configuration['type'] is required" unless options["configuration"]["type"]

    missing_keys = []

    configuration = options["configuration"]
    required_keys = %w(flavor volume_size mnt_volume_size)

    if self.database_service
      raise "application_id is a required key" unless options["application_id"]

      configuration["logical_database"] = "#{self.name}_#{self.application.name}"
    end

    if configuration["type"] == 'custom'
      apps      = configuration["apps"]      ||= {}
      db_master = configuration["db_master"] ||= {}
      db_slaves = configuration["db_slaves"] ||= []
      utils     = configuration["utils"]     ||= []

      missing_keys << "apps" unless apps.any?
      (required_keys + ["count"]).each do |required|
        missing_keys << "apps[#{required}]" unless apps[required]
      end

      unless configuration["database_service_id"]
        missing_keys << "db_master" unless db_master.any?

        required_keys.each do |key|
          missing_keys << "db_master[#{key}]" unless db_master[key]
        end
      end

      db_slaves.each_with_index do |slave, i|
        (required_keys - ["volume_size", "mnt_volume_size"]).each do |key|
          missing_keys << "db_slaves[#{i}][#{key}]" unless slave[key]
        end
      end

      utils.each_with_index do |util, i|
        required_keys.each do |key|
          missing_keys << "utils[#{i}][#{key}]" unless util[key]
        end
      end
    end

    if missing_keys.any?
      raise "Invalid configuration - The following keys are missing from the configuration:\n#{missing_keys.join(",\n")}"
    end

    params = {
      "cluster_configuration" => {
        "configuration" => configuration
      }
    }

    connection.requests.new(self.connection.boot_environment(params.merge("id" => self.id)).body["request"])
  end

  def save!
    requires :application_id, :account_id, :region

    params = {
      "url"         => self.collection.url,
      "account"     => self.account_id,
      "environment" => {
        "name"                      => self.name,
        "application_id"            => self.application_id,
        "region"                    => self.region,
      },
    }

    params["environment"].merge!("database_service" => self.database_service.id) if self.database_service

    if new_record?
      merge_attributes(self.connection.create_environment(params).body["environment"])
    else raise NotImplementedError # update
    end
  end
end
