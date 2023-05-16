describe ContainerImageRegistryController do
  render_views
  before do
    stub_user(:features => :all)
  end

  it "renders index" do
    get :index
    expect(response.status).to eq(302)
    expect(response).to redirect_to(:action => 'show_list')
  end

  it "renders show screen" do
    EvmSpecHelper.create_guid_miq_server_zone
    ems = FactoryBot.create(:ems_kubernetes)
    container_image_registry =
      ContainerImageRegistry.create(:ext_management_system => ems, :name => "Test Image Registry")
    get :show, :params => {:id => container_image_registry.id}
    expect(response.status).to eq(200)
    expect(response.body).to_not be_empty
    expect(assigns(:breadcrumbs)).to eq([{:name => "Container Image Registries",
                                          :url  => "/container_image_registry/show_list?page=&refresh=y"},
                                         {:name => "Test Image Registry (Summary)",
                                          :url  => "/container_image_registry/show/#{container_image_registry.id}"}])
  end

  describe "#show" do
    before do
      EvmSpecHelper.create_guid_miq_server_zone
      login_as FactoryBot.create(:user)
      @image_registry = FactoryBot.create(:container_image_registry)
    end

    subject { get :show, :params => {:id => @image_registry.id} }

    context "render" do
      render_views

      it do
        is_expected.to have_http_status 200
      end
    end
  end

  it "renders show_list" do
    session[:settings] = {:default_search => 'foo',
                          :views          => {:containerimageregistry => 'list'},
                          :perpage        => {:list => 10}}

    EvmSpecHelper.create_guid_miq_server_zone

    get :show_list
    expect(response.status).to eq(200)
    expect(response.body).to_not be_empty
  end

  include_examples '#download_summary_pdf', :container_image_registry
end
