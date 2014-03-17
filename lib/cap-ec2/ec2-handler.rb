module CapEC2
  class EC2Handler
    include CapEC2::Utils

    def initialize
      load_config
      configured_regions = get_regions(fetch(:ec2_region))
      @ec2 = {}
      @elb = {}
      configured_regions.each do |region|
        @ec2[region] = ec2_connect(region)
        @elb[region] = elb_connect(region)
      end
    end

    def ec2_connect(region=nil)
      AWS::EC2.new(
        access_key_id: fetch(:ec2_access_key_id),
        secret_access_key: fetch(:ec2_secret_access_key),
        region: region
      )
    end

    def elb_connect(region)
      elb = AWS::ELB.new(
        access_key_id: fetch(:ec2_access_key_id),
        secret_access_key: fetch(:ec2_secret_access_key),
        region: region 
      )
      elb.load_balancers
    end

    def status_table
      CapEC2::StatusTable.new(
        defined_roles.map {|r| get_servers_for_role(r)}.flatten.uniq {|i| i.instance_id}
      )
    end

    def server_names
      puts defined_roles.map {|r| get_servers_for_role(r)}
                   .flatten
                   .uniq {|i| i.instance_id}
                   .map {|i| i.tags["Name"]}
                   .join("\n")
    end

    def instance_ids
      puts defined_roles.map {|r| get_servers_for_role(r)}
                   .flatten
                   .uniq {|i| i.instance_id}
                   .map {|i| i.instance_id}
                   .join("\n")
    end

    def defined_roles
      Capistrano::Configuration.env.send(:servers).send(:available_roles)
    end

    def stage
      Capistrano::Configuration.env.fetch(:stage).to_s
    end

    def application
      Capistrano::Configuration.env.fetch(:application).to_s
    end

    def tag(tag_name)
      "tag:#{tag_name}"
    end

    def get_servers_for_role(role)
      servers = []
      @ec2.each do |_, ec2|
        instances = ec2.instances
          .filter(tag(project_tag), application)
          .filter('instance-state-code', '16')
        servers << instances.select do |i|
          i.tags[roles_tag] =~ /,{0,1}#{role}(,|$)/ && i.tags[stages_tag] =~ /,{0,1}#{stage}(,|$)/
        end
      end
      servers.flatten
    end

    def get_load_balancers_for_instance(instance_id)
      load_balancers = [] 
      @elb.each do |region, elb|
        elb.each do |lb |
          lb.instances.each do |instance|
            if instance.id == instance_id
              load_balancers << lb.name
            end
          end
        end
      end
      load_balancers.flatten
    end

    def deregister_from_elb(instance_id)
      removed = {}

      @elb.each do |region, elb|
        removed[region] = []
        elb.each do |lb|
          lb.instances.each do |instance|
            if instance.id == instance_id
              removed[region] << lb.name
              lb.instances.deregister(instance_id)
            end
          end
        end
      end
      removed
    end 

    def register_in_elb(instance_id, load_balancers)
      @elb.each do |region, elbs|
        if load_balancers.key?(region)
          load_balancers[region].each do |lb|
            elbs[lb].instances.register(instance_id)
          end
        end
      end
    end
  end
end
