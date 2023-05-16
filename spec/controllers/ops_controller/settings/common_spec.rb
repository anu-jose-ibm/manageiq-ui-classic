describe OpsController do
  context "OpsController::Settings::Common" do
    before do
      MiqDatabase.seed
      MiqRegion.seed
      EvmSpecHelper.local_miq_server(:zone => Zone.seed)
      stub_user(:features => :all)
    end

    context "SmartProxy Affinity" do
      before do
        @zone = FactoryBot.create(:zone)

        @ems = FactoryBot.create(:ext_management_system, :zone => @zone)

        @storage1 = FactoryBot.create(:storage, :ems_id => @ems.id)
        @storage2 = FactoryBot.create(:storage, :ems_id => @ems.id)

        @host1 = FactoryBot.create(:host, :ems_id => @ems.id, :storages => [@storage1])
        @host2 = FactoryBot.create(:host, :ems_id => @ems.id, :storages => [@storage2])

        @svr1 = FactoryBot.create(:miq_server, :zone => @zone)
        @svr2 = FactoryBot.create(:miq_server, :zone => @zone)

        @svr1.vm_scan_host_affinity = [@host1]
        @svr2.vm_scan_host_affinity = [@host2]
        @svr1.vm_scan_storage_affinity = [@storage1]
        @svr2.vm_scan_storage_affinity = [@storage2]
        allow_any_instance_of(MiqServer).to receive_messages(:is_a_proxy? => true)
        allow(MiqServer).to receive(:my_server).and_return(OpenStruct.new('id' => 0, :name => 'name'))

        tree_hash = {
          :trees       => {
            :settings_tree => {
              :active_node => "z-#{@zone.id}"
            }
          },
          :active_tree => :settings_tree,
          :active_tab  => 'settings_smartproxy_affinity'
        }
        controller.instance_variable_set(:@sb, tree_hash)
        controller.instance_variable_set(:@selected_zone, @zone)

        @temp = {}
        controller.instance_variable_set(:@temp, @temp)

        controller.send(:smartproxy_affinity_set_form_vars)
        @edit = session[:edit]
      end

      describe "#smartproxy_affinity_field_changed" do
        before { expect(controller).to receive(:render) }

        it "should select a host when checked" do
          controller.params = {:id => "xx-#{@svr1.id}__host_#{@host2.id}", :check => '1'}
          controller.smartproxy_affinity_field_changed
          expect(@edit[:new][:servers][@svr1.id][:hosts].to_a).to include(@host2.id)
        end

        it "should deselect a host when unchecked" do
          controller.params = {:id => "xx-#{@svr1.id}__host_#{@host1.id}", :check => '0'}
          controller.smartproxy_affinity_field_changed
          expect(@edit[:new][:servers][@svr1.id][:hosts].to_a).not_to include(@host1.id)
        end

        it "should select a datastore when checked" do
          controller.params = {:id => "xx-#{@svr1.id}__storage_#{@storage2.id}", :check => '1'}
          controller.smartproxy_affinity_field_changed
          expect(@edit[:new][:servers][@svr1.id][:storages].to_a).to include(@storage2.id)
        end

        it "should deselect a datastore when unchecked" do
          controller.params = {:id => "xx-#{@svr1.id}__storage_#{@storage1.id}", :check => '0'}
          controller.smartproxy_affinity_field_changed
          expect(@edit[:new][:servers][@svr1.id][:storages].to_a).not_to include(@storage1.id)
        end

        it "should select all child hosts when checked" do
          controller.params = {:id => "xx-#{@svr1.id}__host", :check => '1'}
          controller.smartproxy_affinity_field_changed
          expect(@edit[:new][:servers][@svr1.id][:hosts].to_a.sort).to eq([@host1.id, @host2.id])
        end

        it "should deselect all child hosts when unchecked" do
          controller.params = {:id => "xx-#{@svr1.id}__host", :check => '0'}
          controller.smartproxy_affinity_field_changed
          expect(@edit[:new][:servers][@svr1.id][:hosts].to_a).to eq([])
        end

        it "should select all child datastores when checked" do
          controller.params = {:id => "xx-#{@svr1.id}__storage", :check => '1'}
          controller.smartproxy_affinity_field_changed
          expect(@edit[:new][:servers][@svr1.id][:storages].to_a.sort).to eq([@storage1.id, @storage2.id])
        end

        it "should deselect all child datastores when unchecked" do
          controller.params = {:id => "xx-#{@svr1.id}__storage", :check => '0'}
          controller.smartproxy_affinity_field_changed
          expect(@edit[:new][:servers][@svr1.id][:storages].to_a).to eq([])
        end

        it "should select all child hosts and datastores when checked" do
          controller.params = {:id => "svr-#{@svr1.id}", :check => '1'}
          controller.smartproxy_affinity_field_changed
          expect(@edit[:new][:servers][@svr1.id][:hosts].to_a.sort).to eq([@host1.id, @host2.id])
          expect(@edit[:new][:servers][@svr1.id][:storages].to_a.sort).to eq([@storage1.id, @storage2.id])
        end

        it "should deselect all child hosts and datastores when checked" do
          controller.params = {:id => "svr-#{@svr1.id}", :check => '0'}
          controller.smartproxy_affinity_field_changed
          expect(@edit[:new][:servers][@svr1.id][:hosts].to_a).to eq([])
          expect(@edit[:new][:servers][@svr1.id][:storages].to_a).to eq([])
        end
      end

      describe "#smartproxy_affinity_update" do
        it "updates the SmartProxy host affinities" do
          @svr1.vm_scan_host_affinity = []
          @svr2.vm_scan_host_affinity = []

          # Commit the in-progress edit state (i.e. the initial state)
          controller.send(:smartproxy_affinity_update)
          expect(@svr1.vm_scan_host_affinity).to eq([@host1])
          expect(@svr2.vm_scan_host_affinity).to eq([@host2])
        end

        it "updates the SmartProxy storage affinities" do
          @svr1.vm_scan_storage_affinity = []
          @svr2.vm_scan_storage_affinity = []

          # Commit the in-progress edit state (i.e. the initial state)
          controller.send(:smartproxy_affinity_update)
          expect(@svr1.vm_scan_storage_affinity).to eq([@storage1])
          expect(@svr2.vm_scan_storage_affinity).to eq([@storage2])
        end
      end
    end

    describe "#settings_get_form_vars" do
      before do
        miq_server = FactoryBot.create(:miq_server)
        current = Settings.to_hash
        current[:authentication] = {:ldap_role => true, :mode => 'ldap'}
        edit = {:current => current,
                :new     => copy_hash(current),
                :key     => "settings_authentication_edit__#{miq_server.id}"}
        controller.instance_variable_set(:@edit, edit)
        session[:edit] = edit
        controller.instance_variable_set(:@sb,
                                         :selected_server_id => miq_server.id,
                                         :active_tab         => 'settings_authentication')
        controller.x_node = "svr-#{miq_server.id}"
      end

      it "sets ldap_role to false to make forest entries div hidden" do
        controller.params = {:id                  => 'authentication',
                             :authentication_mode => 'database'}
        controller.send(:settings_get_form_vars)
        expect(assigns(:edit)[:new][:authentication][:ldap_role]).to eq(false)
      end

      it "resets ldap_role to it's original state so forest entries div can be displayed" do
        session[:edit][:new][:authentication][:mode] = 'database'
        controller.params = {:id                  => 'authentication',
                             :authentication_mode => 'ldap'}
        controller.send(:settings_get_form_vars)
        expect(assigns(:edit)[:new][:authentication][:ldap_role]).to eq(true)
      end
    end

    describe "#pglogical_save_subscriptions" do
      before { allow(controller).to receive(:javascript_flash) }

      context "remote" do
        let(:params) { {:replication_type => "remote"} }

        it "queues operation to set the region as a remote type" do
          controller.params = params
          controller.send(:pglogical_save_subscriptions)
          queue_item = MiqQueue.find_by(:method_name => "replication_type=")
          expect(queue_item.args).to eq([:remote])
        end

        it "task name is visible in the resulting flash message" do
          controller.params = params
          controller.send(:pglogical_save_subscriptions)
          expect(assigns(:flash_array).first[:message]).to eq("Replication configuration save initiated. Check status of task \"Configure the database to be a replication remote region\" on My Tasks screen")
        end
      end

      context "global" do
        let(:db_save)       { "DbName_For_Subscription_To_Save" }
        let(:db_remove)     { "DbName_For_Subscription_To_Remove" }
        let(:subscriptions) { {"0" => {"dbname" => db_save}, "1" => {'remove' => "true", "dbname" => db_remove}} }
        let(:params)        { {:replication_type => "global", :subscriptions => subscriptions} }

        it "queues operation to save and/or remove subscriptions settings for the global region" do
          controller.params = params
          controller.send(:pglogical_save_subscriptions)
          queue_item = MiqQueue.find_by(:method_name => "save_global_region")
          expect(queue_item.args[0][0].dbname).to eq(db_save)
          expect(queue_item.args[0][1].dbname).to eq(db_remove)
        end

        it "encrypts subscription's password before queuing save operation" do
          password = "some_password"
          subscriptions["0"] = {"password" => password}
          controller.params = params
          controller.send(:pglogical_save_subscriptions)
          queue_item = MiqQueue.find_by(:method_name => "save_global_region")
          queued_password = queue_item.args[0][0].password
          expect(ManageIQ::Password.encrypted?(queued_password)).to be(true)
          expect(ManageIQ::Password.decrypt(queued_password)).to eq(password)
        end
      end

      context "none" do
        let(:params) { {:replication_type => "none"} }

        it "queues operations to set replication to none" do
          controller.params = params
          controller.send(:pglogical_save_subscriptions)
          queue_item = MiqQueue.find_by(:method_name => "replication_type=")
          expect(queue_item.args[0]).to eq(:none)
        end
      end
    end

    describe '#settings_get_info' do
      before { MiqRegion.seed }

      let(:edit) { controller.instance_variable_get(:@edit) }

      context 'help menu' do
        it 'current and new in the edit hash equals' do
          controller.instance_variable_set(:@sb, :active_tab => 'settings_help_menu')
          controller.send(:settings_get_info, 'root-0')
          expect(edit[:new]).to eq(edit[:current])
        end
      end

      context 'get advanced config settings' do
        it 'for selected server' do
          miq_server = FactoryBot.create(:miq_server)
          enc_pass = ManageIQ::Password.encrypt('pa$$word')
          Vmdb::Settings.save!(
            miq_server,
            :http_proxy => {
              :default => {
                :host     => "proxy.example.com",
                :user     => "user",
                :password => enc_pass,
                :port     => 80
              }
            }
          )
          miq_server.reload
          allow(controller).to receive(:x_node).and_return("svr-#{miq_server.id}")
          controller.instance_variable_set(:@sb, :active_tab => 'settings_advanced')
          controller.send(:settings_get_info, "svr-#{miq_server.id}")
          config = assigns(:edit)[:current][:file_data]
          expect(config).to include(":host: proxy.example.com")
          expect(config).to include(":user: user")
          expect(config).to include(":password: #{enc_pass}")
          expect(config).to include(":port: 80")
        end

        it 'for selected zone' do
          zone = FactoryBot.create(:zone)
          enc_pass = ManageIQ::Password.encrypt('pa$$word')
          Vmdb::Settings.save!(
            zone,
            :http_proxy => {
              :default => {
                :host     => "proxy.example.com",
                :user     => "user",
                :password => enc_pass,
                :port     => 80
              }
            }
          )
          zone.reload
          allow(controller).to receive(:x_node).and_return("svr-#{zone.id}")
          controller.instance_variable_set(:@sb, :active_tab => 'settings_advanced')
          controller.send(:settings_get_info, "z-#{zone.id}")
          config = assigns(:edit)[:current][:file_data]
          expect(config).to include(":host: proxy.example.com")
          expect(config).to include(":user: user")
          expect(config).to include(":password: #{enc_pass}")
          expect(config).to include(":port: 80")
        end
      end
    end

    describe "#update_server_zone" do
      let(:server) { FactoryBot.create(:miq_server) }

      it "returns true when no zone is set" do
        original_zone = server.zone
        new_data = {:server => {:zone => nil}}
        controller.instance_variable_set(:@edit, :new => new_data)

        expect(controller.send(:update_server_zone, server)).to be_truthy
        expect(server.reload.zone).to eq(original_zone)
      end

      it "returns true when the zone is unchanged" do
        original_zone = server.zone
        new_data = {:server => {:zone => original_zone.name}}
        controller.instance_variable_set(:@edit, :new => new_data)

        expect(controller.send(:update_server_zone, server)).to be_truthy
        expect(server.reload.zone).to eq(original_zone)
      end

      it "returns true when the zone is updated successfully" do
        new_zone = FactoryBot.create(:zone)
        new_data = {:server => {:zone => new_zone.name}}
        controller.instance_variable_set(:@edit, :new => new_data)

        expect(controller.send(:update_server_zone, server)).to be_truthy
        expect(server.reload.zone).to eq(new_zone)
      end

      it "returns false when the zone update fails" do
        original_zone = server.zone
        new_data = {:server => {:zone => Zone.maintenance_zone.name}}
        controller.instance_variable_set(:@edit, :new => new_data)

        expect(controller.send(:update_server_zone, server)).to be_falsey
        expect(server.reload.zone).to eq(original_zone)
      end
    end

    describe '#settings_update_save' do
      context "save config settings" do
        it 'for selected server' do
          miq_server = FactoryBot.create(:miq_server)
          allow(controller).to receive(:x_node).and_return("svr-#{miq_server.id}")
          controller.instance_variable_set(:@sb,
                                           :active_tab         => 'settings_advanced',
                                           :selected_server_id => miq_server.id)
          controller.params = {:id => 'advanced'}
          data = {:api => {:token_ttl => "1.day"}}.to_yaml
          controller.instance_variable_set(:@edit,
                                           :new     => {:file_data => data},
                                           :current => {:file_data => data},
                                           :key     => "settings_advanced_edit__#{miq_server.id}")
          session[:edit] = assigns(:edit)
          expect(controller).to receive(:render)
          expect(Vmdb::Settings).to receive(:reload!)

          controller.send(:settings_update_save)
          controller.send(:fetch_advanced_settings, miq_server)
          expect(SettingsChange.first).to have_attributes(:key => '/api/token_ttl', :value => "1.day")
        end

        it 'for selected zone' do
          zone = FactoryBot.create(:zone)
          allow(controller).to receive(:x_node).and_return("z-#{zone.id}")
          controller.instance_variable_set(:@sb,
                                           :active_tab         => 'settings_advanced',
                                           :selected_server_id => zone.id)
          controller.params = {:id => 'advanced'}
          data = {:api => {:token_ttl => "1.day"}}.to_yaml
          controller.instance_variable_set(:@edit,
                                           :new     => {:file_data => data},
                                           :current => {:file_data => data},
                                           :key     => "settings_advanced_edit__#{zone.id}")
          session[:edit] = assigns(:edit)
          expect(controller).to receive(:render)
          expect(Vmdb::Settings).to receive(:reload!)

          controller.send(:settings_update_save)
          controller.send(:fetch_advanced_settings, zone)
          expect(SettingsChange.first).to have_attributes(:key => '/api/token_ttl', :value => "1.day")
        end
      end

      context "save server name in server settings only when 'Server' is active tab" do
        before do
          @miq_server = FactoryBot.create(:miq_server)
          allow(controller).to receive(:x_node).and_return("svr-#{@miq_server.id}")
          controller.instance_variable_set(:@sb,
                                           :active_tab         => 'settings_server',
                                           :selected_server_id => @miq_server.id)
          controller.params = {:id => 'server'}
          @current = Settings.to_hash
          @new = Settings.to_hash
          @new[:server][:name] = ''
          controller.instance_variable_set(:@edit,
                                           :new     => @new,
                                           :current => @current,
                                           :key     => "settings_server_edit__#{@miq_server.id}")
          session[:edit] = assigns(:edit)
          expect(controller).to receive(:render)
        end

        it "does not allow to save blank appliance name" do
          controller.send(:settings_update_save)
          expect(assigns(:flash_array).first[:message]).to include("Appliance name must be entered.")
        end

        it "saves new server name for server record" do
          @new[:server][:name] = 'Foo'
          controller.send(:settings_update_save)
          @miq_server.reload
          expect(@miq_server.name).to eq("Foo")
        end

        it "does not update server name when active tab is Authentication tab" do
          controller.instance_variable_set(:@sb,
                                           :active_tab         => 'settings_authentication',
                                           :selected_server_id => @miq_server.id)
          @new[:server][:name] = 'Foo'
          controller.send(:settings_update_save)
          @miq_server.reload
          expect(@miq_server.name).to_not eq("Foo")
        end
      end
    end

    describe '#settings_set_form_vars_server' do
      context 'sets values correctly' do
        it 'for server in non-current zone' do
          zone = FactoryBot.create(:zone)
          server = FactoryBot.create(:miq_server, :zone => zone)
          controller.instance_variable_set(:@sb, :selected_server_id => server.id)
          controller.send(:settings_set_form_vars_server)
          edit_current = assigns(:edit)
          expect(edit_current[:current][:server][:zone]).to eq(zone.name)
        end

        it 'for server in default zone' do
          server = FactoryBot.create(:miq_server, :zone => Zone.find_by(:name => "default"))
          controller.instance_variable_set(:@sb, :selected_server_id => server.id)
          controller.send(:settings_set_form_vars_server)
          edit_current = assigns(:edit)
          expect(edit_current[:current][:server][:zone]).to eq("default")
        end

        it 'sets the server name' do
          server = FactoryBot.create(:miq_server)
          controller.instance_variable_set(:@sb, :selected_server_id => server.id)
          controller.send(:settings_set_form_vars_server)
          edit_current = assigns(:edit)
          expect(edit_current[:current][:server][:name]).to eq(server.name)
        end
      end
    end
  end
end
