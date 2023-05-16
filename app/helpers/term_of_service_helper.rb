module TermOfServiceHelper
  ASSIGN_TOS = {
    # This set of assignments was created for miq_alerts
    "ExtManagementSystem" => {
      "enterprise"                 => N_("The Enterprise"),
      "ext_management_system"      => N_("Selected Providers"),
      "ext_management_system-tags" => N_("Tagged Providers")
    },
    "EmsCluster"          => {
      "ems_cluster"      => N_("Selected Clusters"),
      "ems_cluster-tags" => N_("Tagged Clusters")
    },
    "Host"                => {
      "host"      => N_("Selected Hosts"),
      "host-tags" => N_("Tagged Hosts")
    },
    "Vm"                  => {
      "ems_folder"         => N_("Selected Folders"),
      "resource_pool"      => N_("Selected Resource Pools"),
      "resource_pool-tags" => N_("Tagged Resource Pools"),
      "vm-tags"            => N_("Tagged VMs and Instances")
    },
    "Storage"             => {
      "enterprise"   => N_("The Enterprise"),
      "storage"      => N_("Selected Datastores"),
      "storage-tags" => N_("Tagged Datastores"),
      "tenant"       => N_("Tenants")
    },
    "MiqServer"           => {
      "miq_server" => N_("Selected Servers"),
    },
    "ContainerNode"       => {
      "enterprise" => N_("The Enterprise"),
    },
    "ContainerProject"    => {
      "enterprise" => N_("The Enterprise"),
    },
    # This set of assignments was created for chargeback_rates
    :chargeback_compute   => {
      "enterprise"             => N_("The Enterprise"),
      "ext_management_system"  => N_("Selected Providers"),
      "ems_cluster"            => N_("Selected Clusters"),
      "vm-tags"                => N_("Tagged VMs and Instances"),
      "configured_system-tags" => N_("Tagged Configured Systems"),
      "container_image-tags"   => N_("Tagged Container Images"),
      "container_image-labels" => N_("Labeled Container Images"),
      "tenant"                 => N_("Tenants")
    },
    "PhysicalServer"      => {
      "physical_server" => N_("Selected Servers")
    }
  }.freeze

  ASSIGN_TOS[:chargeback_storage] = ASSIGN_TOS["Storage"]

  ASSIGN_TOS["EmsCluster"].merge!(ASSIGN_TOS["ExtManagementSystem"])
  ASSIGN_TOS["Host"].merge!(ASSIGN_TOS["EmsCluster"])
  ASSIGN_TOS["Vm"].merge!(ASSIGN_TOS["Host"])

  ASSIGN_TOS.freeze
end
