class TreeBuilderAlertProfileObj < TreeBuilder
  def initialize(name, type, sandbox, build = true, assign = nil)
    @assign = {
      :new     => assign[:new],
      :current => assign[:current]
    }

    build = false unless @assign[:new][:assign_to]
    super(name, type, sandbox, build)
  end

  def override(node, object, _pid, _options)
    identifier = (object.name.presence || object.description)
    if object.kind_of?(MiddlewareServer)
      identifier += "-" + object.hostname
    end

    if @assign[:new][:assign_to].ends_with?("-tags")
      node[:icon] = "fa fa-tag"
    elsif @assign[:new][:assign_to] == "ext_management_system"
      node[:image] = "svg/vendor-#{object.image_name}.svg"
    elsif @assign[:new][:assign_to] == "resource_pool"
      node[:icon] = "pficon-resource_pool"
    elsif @assign[:new][:assign_to] == "tenant"
      node[:image] = ActionController::Base.helpers.image_path("100/tenant.png")
    else
      node[:image] = ActionController::Base.helpers.image_path("100/#{@assign[:new][:assign_to]}.png")
    end

    node[:title] = identifier
    node[:cfmeNoClick] = true
    node[:hideCheckbox] = false
    node[:select] = @assign[:new][:objects].include?(object.id)
    node
  end

  def tree_init_options(_tree_name)
    {
      :expand => true
    }
  end

  def set_locals_for_render
    locals = super
    locals.merge!(
      :id_prefix  => "obj_treebox2",
      :oncheck    => "miqOnCheckHandler",
      :check_url  => "alert_profile_assign_changed/",
      :checkboxes => true,
    )
  end

  def root_options
    t = @assign[:new][:assign_to].ends_with?("-tags") ? "Tags" : ui_lookup(:tables => @assign[:new][:assign_to])
    {
      :title        => t,
      :tooltip      => "",
      :icon        => "pficon pficon-folder-open",
      :hideCheckbox => true,
      :cfmeNoClick  => true,
      :expand       => true
    }
  end

  def x_get_tree_roots(count_only, _options)
    @objects = []
    if !(@assign[:new][:assign_to] == "enterprise") && @assign[:new][:assign_to]
      # No further selection needed for enterprise
      # Assign to selected
      if @assign[:new][:assign_to].ends_with?("-tags") && @assign[:new][:cat]
        # Tag category selected
        @objects = Classification.find(@assign[:new][:cat]).entries
      else
        # Model selected
        @objects = @assign[:new][:assign_to].camelize.constantize.all
      end
    end
    count_only_or_objects(count_only, @objects.sort_by { |o| (o.name.presence || o.description).downcase })
  end
end
