{
  programs = [
    "bri_handle"
    "tna_counter"
    "tna_idletimeout"
    "tna_pktgen"
    "tna_range_match"
    "tna_timestamp"
    "tna_32q_2pipe"
    "tna_custom_hash"
    "tna_lpm_match"
    "tna_port_metadata"
    "tna_register"
    "bri_with_pdfixed_thrift"
    "tna_digest"
    "tna_meter_bytecount_adjust"
    "tna_port_metadata_extern"
    "tna_resubmit"
    "tna_action_profile"
    "tna_dkm"
    "tna_meter_lpf_wred"
    "tna_ports"
    "tna_simple_switch"
    "tna_action_selector"
    "tna_dyn_hashing"
    "tna_mirror"
    "tna_proxy_hash"
    "tna_snapshot"
    "tna_bridged_md"
    ## Either hangs or takes too long to complete
    # "tna_exact_match"
    "tna_multicast"
    "tna_pvs"
    "tna_symmetric_hash"
    "tna_checksum"
    "tna_field_slice"
    "tna_operations"
    "tna_random"
    "tna_ternary_match"
    ## These require special build procedures, TBD
    # "p4rt_utests"
    # "bri_set_forwarding_pipeline"
    # "t2na_counter_true_egress_accounting"
    # "tna_32q_multiprogram"
  ];
  args = {
    tna_custom_hash = {
      pythonModules = [ "crcmod" ];
    };
    tna_proxy_hash = {
      pythonModules = [ "crcmod" ];
    };
  };
}
