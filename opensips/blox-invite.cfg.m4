# /* Blox is an Opensource Session Border Controller
#  * Copyright (c) 2015-2018 "Blox" [http://www.blox.org]
#  * 
#  * This file is part of Blox.
#  * 
#  * Blox is free software: you can redistribute it and/or modify
#  * it under the terms of the GNU General Public License as published by
#  * the Free Software Foundation, either version 3 of the License, or
#  * (at your option) any later version.
#  * 
#  * This program is distributed in the hope that it will be useful,
#  * but WITHOUT ANY WARRANTY; without even the implied warranty of
#  * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  * GNU General Public License for more details.
#  * 
#  * You should have received a copy of the GNU General Public License
#  * along with this program. If not, see <http://www.gnu.org/licenses/> 
#  */


route[ROUTE_INVITE] {
    if(method == "INVITE") {
        if($si == $avp(LANIP) || $si == $avp(WANIP)) { #Source IP Matching LAN or WAN IP
            xdbg("Skipping INVITE generated locally by the server\n" );
            drop();
            exit;
        }

        if($avp(LAN)) { #/* PBX to SBC */
            $avp(TRUNK) = null;
            xdbg("Got from $Ri LAN\n");
            $avp(uuid) = "LCR:" + $avp(LAN) ;

            if(cache_fetch("local","$avp(uuid)",$avp(LCR))) {
                xdbg("Loaded from cache $avp(uuid): $avp(LCR)\n");
            } else if (avp_db_load("$avp(uuid)","$avp(LCR)/blox_config")) {
                #NO Cache for LCR Right now
                #cache_store("local","$avp(uuid)","$avp(LCR)");
                #xdbg("Stored in cache $avp(uuid): $avp(LCR)\n");
            } else {
                $avp(LCR) = null;
            }

            if($avp(LCR)) {
                $var(i) = 0; 
                $var(loop) = 1;
                while($var(loop) && $(avp(LCR)[$var(i)])) {
                    xdbg("Got from LAN LCR Matching $(avp(LCR)[$var(i)])\n");
                    $var(LCR) = $(avp(LCR)[$var(i)]);
                    $var(src) = $si + ":" + $sp ;
                    xdbg("Got from LAN LCR Matching $var(src) == $(var(LCR){param.value,PBX})\n");
                    if($var(src) == $(var(LCR){param.value,PBX})) {
                        $var(g) = $(var(LCR){param.value,Group});
                        $avp(g) = $(var(g){s.int});
                        $var(loop) = null;
                    }
                    $var(i) = $var(i) + 1;
                }

                if($var(loop) != null) {
                    xlog("L_NOTICE", "LCR: SIP Profile access denied for $si:$sp \n");
                    sl_send_reply("603", "Declined");
                    exit;
                }
                
                $var(oru) = $ru ;

                xdbg("Group: $var(g)\n"); #Dont print directly without substr
                if (do_routing("$avp(g)",,,,"$var(gw_attributes)")) { #/* Goes to configured route */
                    $avp(trunk_uuid) = $var(gw_attributes) ; 
                    route(OUTBOUND_CALL_ACCESS_CONTROL);
                    while (!isflagset(OUTBOUND_CALL_ACCESS_CONTROL)) {
                        if(use_next_gw(,"$var(gw_attributes)")) {
                            xlog("L_NOTICE", "LCR: Next GW found, PBX $si:$sp $var(gw_attributes)\n");
                            $avp(trunk_uuid) = $var(gw_attributes) ; 
                            route(OUTBOUND_CALL_ACCESS_CONTROL);
                        } else {
                            xlog("L_WARN", "No Next GW found for LCR, PBX $si:$sp $var(gw_attributes)\n");
                            send_reply("503", "No Rules matching the URI");
                            exit;
                        }
                    }
                    append_to_reply("Diversion: <$ru>;reason=deflection\r\n");

                    $avp(LAN) = $(var(gw_attributes){uri.param,LAN});
                    if($avp(LAN)) {
                        xdbg("Group: $avp(LAN)\n"); #Dont print directly without substr
                        if(cache_fetch("local","$avp(LAN)",$avp(LANProfile))) {
                            xdbg("Loaded from cache $avp(LAN): $avp(LANProfile)\n");
                        } else if (avp_db_load("$avp(LAN)","$avp(LANProfile)/blox_profile_config")) {
                            cache_store("local","$avp(LAN)","$avp(LANProfile)");
                            xdbg("Stored in cache $avp(LAN): $avp(LANProfile)\n");
                        } else {
                            $avp(LANProfile) = null;
                            xdbg("Drop MESSAGE $ru from $si : $sp\n" );
                            drop(); # /* Default 5060 open to accept packets from LAN side, but we don't process it */
                            exit;
                        }
                        $var(RDIP) = $(avp(LANProfile){uri.host});
                        $var(RDPORT) = $(avp(LANProfile){uri.port});
                        #Manipulated Adding, Striping Prefix, Suffix
                        $var(ru) = "sip:" + $rU + "@" + $var(RDIP) + ":" + $var(RDPORT) ; #/* 5062 should be Unique port for the Gateway to set in Diversion IP:PORT */
                        xlog("L_NOTICE","{ \"LCR-REDIRECT\" : { \"FURI\": \"$fu;tag=$ft\", \"RURI-ORG\": \"$var(oru)\", \"RURI\": \"$ru\", \"REDIRECT\": \"$var(ru)\", \"SRCIP\": \"$si:$sp\", \"DSTIP\": \"$Ri:$Rp\", \"TS\": $TS } }"); /* NOTICE USED FOR LCR AND LOGGED INTO lcr.log */
                        $ru = $var(ru) ;
                        sl_send_reply("302","LCR Redirect");
                        exit;
                    } else {
                        xlog("L_NOTICE", "LCR: No LAN: $var(g)\n"); #Dont print directly without substr
                    }
                } else {
                        xlog("L_NOTICE", "LCR: No Next GW found for LCR, PBX $si:$sp $var(gw_attributes)\n");
                        send_reply("503", "No Rules matching the URI");
                        exit;
                }
            }

            if(!$avp(TRUNK)) { #If not already set by LCR
                $avp(uuid) = "TRUNK:" + $avp(LAN) ;
                if(cache_fetch("local","$avp(uuid)",$avp(TRUNK))) {
                    xdbg("Loaded from cache $avp(uuid): $avp(TRUNK)\n");
                } else if (avp_db_load("$avp(uuid)","$avp(TRUNK)/blox_config")) {
                    cache_store("local","$avp(uuid)","$avp(TRUNK)");
                    xdbg("Stored in cache $avp(uuid): $avp(TRUNK)\n");
                } else {
                    $avp(TRUNK) = null;
                }
            }

            if($avp(TRUNK)) {
                xdbg("Routing Forwarded PBX MESSAGE $avp(TRUNK)\n");
                $var(TRUNKUSER) = $(avp(TRUNK){uri.user});
                $var(TRUNKIP) = $(avp(TRUNK){uri.host});
                $var(TRUNKPORT) = $(avp(TRUNK){uri.port});
                $var(TRUNKDOMAIN) = $(avp(TRUNK){uri.domain});
                $avp(WAN)  = $(avp(TRUNK){uri.param,WAN});
                $avp(T38Param)  = $(avp(TRUNK){uri.param,T38Param});
                $avp(MEDIA)  = $(avp(TRUNK){uri.param,MEDIA});
                $avp(GWID) = $(avp(TRUNK){uri.param,GWID});
                $avp(SrcSRTP) = $(avp(TRUNK){uri.param,LANSRTP});
                $avp(DstSRTP) = $(avp(TRUNK){uri.param,WANSRTP});

                if($avp(WAN)) {
                    if(cache_fetch("local","$avp(WAN)",$avp(WANProfile))) {
                        xdbg("Loaded from cache $avp(WAN): $avp(WANProfile)\n");
                    } else if (avp_db_load("$avp(WAN)","$avp(WANProfile)/blox_profile_config")) {
                        cache_store("local","$avp(WAN)","$avp(WANProfile)");
                        xdbg("Stored in cache $avp(WAN): $avp(WANProfile)\n");
                    } else {
                        $avp(WANProfile) = null;
                        xdbg("Drop MESSAGE $ru from $si : $sp\n" );
                        drop(); # /* Default 5060 open to accept packets from WAN side, but we don't process it */
                        exit;
                    }
                    #avp_db_query("SELECT uuid FROM blox_config WHERE value = '$avp(WAN)' AND attribute = 'WAN' LIMIT 1", "$avp(WANProfile)");

                    if(!has_totag()) {
                        xdbg("$avp(TRUNK)/$var(TRUNKUSER)/ $var(TRUNKIP)/$var(TRUNKPORT)/$avp(SIPProfile)\n");
                        $avp(trunk_uuid) = $avp(TRUNK) ; 
                        setflag(487); /* Send response 487 if GW not available */
                        route(OUTBOUND_CALL_ACCESS_CONTROL);
                        if(!isflagset(OUTBOUND_CALL_ACCESS_CONTROL)) {
                            xlog("L_INFO", "Dropping SIP Method $rm received from $fu $si $sp to $ru ($avp(rcv))\n");
                            drop();
                            exit;
                        }
                        topology_hiding("C");
                        $dlg_val(MediaProfileID) = $(avp(TRUNK){uri.param,MEDIA}) ;
                        $dlg_val(from) = $fu ;
                        $dlg_val(request) = $ru ;
                        $dlg_val(channel) = "sip:" + $si + ":" + $sp;
                        xdbg("Storing the cseq offset for $ft\n") ;
                        if($(hdr(Diversion))) {
                            $dlg_val(dchannel) = $avp(TRUNK) + ";Diversion=" + $(hdr(Diversion)) ;
                        } else {
                            $dlg_val(dchannel) = $avp(TRUNK) ;
                        }
                        setflag(ACC_FLAG_CDR_FLAG);
                        setflag(ACC_FLAG_LOG_FLAG);
                        setflag(ACC_FLAG_DB_FLAG);
                        setflag(ACC_FLAG_FAILED_TRANSACTION);
                        append_hf("P-hint: tophide applied\r\n"); 
                    };
                    if( route_to_gw("$avp(GWID)") ) {
                        if(!has_totag()) { #Set From/To Execute inital time
                            if(cache_fetch("local","$avp(WAN)",$avp(WANProfile))) {
                                xdbg("Loaded from cache $avp(WAN): $avp(WANProfile)\n");
                            } else if (avp_db_load("$avp(WAN)","$avp(WANProfile)/blox_profile_config")) {
                                cache_store("local","$avp(WAN)","$avp(WANProfile)");
                                xdbg("Stored in cache $avp(WAN): $avp(WANProfile)\n");
                            } else {
                                $avp(WANProfile) = null;
                                xlog("L_WARN", "No WAN profile Drop MESSAGE $ru from $si : $sp\n" );
                                drop(); # /* Default 5060 open to accept packets from WAN side, but we don't process it */
                                exit;
                            }
                            if($avp(WANProfile)) {
                                $avp(WANIP) = $(avp(WANProfile){uri.host});
                                $avp(WANPORT) = $(avp(WANProfile){uri.port});
                                $avp(WANPROTO) = $(avp(WANProfile){uri.param,transport});
                                $avp(WANADVIP) = $(avp(WANProfile){uri.param,advip});
                                $avp(WANADVPORT) = $(avp(WANProfile){uri.param,advport});

                                $var(to) = "sip:" + $rU + "@" + $var(TRUNKIP) + ":" + $var(TRUNKPORT) ;
                                uac_replace_to("$var(to)");
                                if($avp(WANADVIP)) {
                                    $var(from) = "sip:" + $var(TRUNKUSER) + "@" + $avp(WANADVIP) + ":" + $var(WANADVPORT) ;
                                } else {
                                    $var(from) = "sip:" + $var(TRUNKUSER) + "@" + $avp(WANIP) + ":" + $var(WANPORT) ;
                                }
                                uac_replace_from("$var(from)");
                            } else {
                                xlog("L_ERROR", "No WAN Profile, Leaking through To/From Header\n");
                            }
                            set_dlg_flag("DLG_FLAG_LAN2WAN") ;
                        }
                        remove_hf("Diversion");
			            $du = $ru ;
			            if($var(TRUNKDOMAIN)) {
			            	$ru = "sip:" + $tU + "@" + $var(TRUNKDOMAIN) ;
			            }
                        t_on_failure("LAN2WAN");
                        xdbg("Routing $ru to $du from $si : $sp via $fs\n" );
                        route(LAN2WAN);
                    } else {
                        xlog("L_INFO", "Failed to route to $avp(GWID) $avp(TRUNK) from $si : $sp\n" );
                    }
                    exit;
                }

                xdbg("SIP Profile for $si:$sp access denied\n");
                sl_send_reply("603", "Declined");
                exit;
            } else {
                $avp(uuid) = "PBX:" + $avp(LAN) ;
                if(cache_fetch("local","$avp(uuid)",$avp(PBX))) {
                    xdbg("Loaded from cache $avp(uuid): $avp(PBX)\n");
                } else if (avp_db_load("$avp(uuid)","$avp(PBX)/blox_config")) {
                    cache_store("local","$avp(uuid)","$avp(PBX)");
                    xdbg("Stored in cache $avp(uuid): $avp(PBX)\n");
                } else {
                    xlog("L_WARN", "SIP Profile for $si:$sp access denied\n");
                    sl_send_reply("603", "Declined");
                    exit;
                }

                if($avp(PBX)) {
                    xdbg("Got route $Ri RE\n");
                    #/* Check Roaming Extension routing */
                    $var(PBXIP) = $(avp(PBX){uri.host}) ;
                    $var(PBXPORT) = $(avp(PBX){uri.port}) ;
                    $avp(WAN) = $(avp(PBX){uri.param,WAN});
                    $avp(T38Param)  = $(avp(PBX){uri.param,T38Param});
                    $avp(MEDIA)  = $(avp(PBX){uri.param,MEDIA});
                    $avp(SrcSRTP) = $(avp(PBX){uri.param,LANSRTP});
                    $avp(DstSRTP) = $(avp(PBX){uri.param,WANSRTP});
                    if(cache_fetch("local","$avp(WAN)",$avp(WANProfile))) {
                        xdbg("Loaded from cache $avp(WAN): $avp(WANProfile)\n");
                    } else if (avp_db_load("$avp(WAN)","$avp(WANProfile)/blox_profile_config")) {
                        cache_store("local","$avp(WAN)","$avp(WANProfile)");
                        xdbg("Stored in cache $avp(WAN): $avp(WANProfile)\n");
                    } else {
                        $avp(WANProfile) = null;
                        xlog("L_INFO", "Drop MESSAGE $ru from $si : $sp\n" );
                        drop(); # /* Default 5060 open to accept packets from WAN side, but we don't process it */
                        exit;
                    }
                    if($avp(WANProfile)) {
                        $avp(WANIP) = $(avp(WANProfile){uri.host});
                        $avp(WANPORT) = $(avp(WANProfile){uri.port});
                        $avp(WANPROTO) = $(avp(WANProfile){uri.param,transport});
                        $avp(WANADVIP) = $(avp(WANProfile){uri.param,advip});
                        $avp(WANADVPORT) = $(avp(WANProfile){uri.param,advport});
                        $fs = $avp(WANPROTO) + ":" + $avp(WANIP) + ":" + $avp(WANPORT);
                    }

                    #search for aor mapped to pbx wan profile
                    $var(aor) = "sip:" + $tU + "@" + $avp(WANIP) + ":" + $avp(WANPORT) ;
                    xdbg("Looking for $var(aor) in locationpbx\n");

                    # /* Last Check for Roaming Extension */
                    if (!lookup("locationpbx","m", "$var(aor)")) { ; #/* Find RE Registered to US */
                        switch ($retcode) {
                            case -1:
                            case -3:
                                t_newtran();
                                t_on_failure("WAN2LAN");
                                t_reply("404", "Not Found");
                                exit;
                            case -2:
                                append_hf("Allow: INVITE, ACK, REFER, NOTIFY, CANCEL, BYE, REGISTER" );
                                sl_send_reply("405", "Method Not Allowed");
                                exit;
                        }
                    };

                    if(!has_totag()) {
                        create_dialog("PpB");
                        $dlg_val(MediaProfileID) = $(avp(PBX){uri.param,MEDIA}) ;
                        $dlg_val(from) = $fu ;
                        $dlg_val(request) = $ru ;
                        $dlg_val(channel) = "sip:" + $si + ":" + $sp;
                        $dlg_val(dchannel) = $du ;
                        topology_hiding("C");
                        setflag(ACC_FLAG_CDR_FLAG);
                        setflag(ACC_FLAG_LOG_FLAG);
                        setflag(ACC_FLAG_DB_FLAG);
                        setflag(ACC_FLAG_FAILED_TRANSACTION);
                        append_hf("P-hint: tophide applied\r\n"); 
                        set_dlg_flag("DLG_FLAG_LAN2WAN") ;
                    };

                    if($avp(WANADVIP)) {
                        $var(to) = "sip:" + $rU + "@" + $avp(WANADVIP) + ":" + $avp(WANADVPORT) ;
                        $var(from) = "sip:" + $fU + "@" + $avp(WANADVIP) + ":" + $avp(WANADVPORT) ;
                    } else {
                        $var(to) = "sip:" + $rU + "@" + $avp(WANIP) + ":" + $avp(WANPORT) ;
                        $var(from) = "sip:" + $fU + "@" + $avp(WANIP) + ":" + $avp(WANPORT) ;
                    }
                    uac_replace_to("$var(to)");
                    uac_replace_from("$var(from)");
                    xlog("L_INFO","Found PBX Requesting $ru -> $var(to)/$du -> $var(from)" );

                    route(LAN2WAN);
                    exit;
                }
            }
        } else if ($avp(WAN)) { #WAN
            xdbg("Got from $Ri WAN\n");
            $avp(uuid) = "TRUNK:" + $avp(WAN) ;
            if(cache_fetch("local","$avp(uuid)",$avp(TRUNK))) {
                xdbg("Loaded from cache $avp(uuid): $avp(TRUNK)\n");
            } else if (avp_db_load("$avp(uuid)","$avp(TRUNK)/blox_config")) {
                cache_store("local","$avp(uuid)","$avp(TRUNK)");
                xdbg("Stored in cache $avp(uuid): $avp(TRUNK)\n");
            } else {
                $avp(TRUNK) = null;
            }

            if($avp(TRUNK)) {
                xdbg("Got from $Ri TRUNK $avp(TRUNK)\n");
                #/* INBOUND Trunk Call */
                $var(TRUNKUSER) = $(avp(TRUNK){uri.user});
                $var(TRUNKIP) = $(avp(TRUNK){uri.host});
                $var(TRUNKPORT) = $(avp(TRUNK){uri.port});
                $avp(T38Param)  = $(avp(TRUNK){uri.param,T38Param});
                $avp(MEDIA)  = $(avp(TRUNK){uri.param,MEDIA});
                $avp(SrcSRTP) = $(avp(TRUNK){uri.param,WANSRTP});
                $avp(DstSRTP) = $(avp(TRUNK){uri.param,LANSRTP});
                $avp(WAN) = $(avp(TRUNK){uri.param,WAN});

                if(cache_fetch("local","$avp(WAN)",$avp(WANProfile))) {
                    xdbg("Loaded from cache $avp(WAN): $avp(WANProfile)\n");
                } else if (avp_db_load("$avp(WAN)","$avp(WANProfile)/blox_profile_config")) {
                    cache_store("local","$avp(WAN)","$avp(WANProfile)");
                    xdbg("Stored in cache $avp(WAN): $avp(WANProfile)\n");
                } else {
                    $avp(WANProfile) = null;
                    xlog("L_INFO", "Drop MESSAGE $ru from $si : $sp\n" );
                    drop(); # /* Default 5060 open to accept packets from WAN side, but we don't process it */
                    exit;
                }

                if($avp(WANProfile)) {
                    $avp(WANIP) = $(avp(WANProfile){uri.host});
                    $avp(WANPORT) = $(avp(WANProfile){uri.port});
                    $avp(WANPROTO) = $(avp(WANProfile){uri.param,transport});
                    $avp(WANADVIP) = $(avp(WANProfile){uri.param,advip});
                    $avp(WANADVPORT) = $(avp(WANProfile){uri.param,advport});
                }

                if (!lookup("locationtrunk","m")) { ; /* Find PBX Registered to US */
                    xdbg("Error no registration to SBC for TRUNK $avp(TRUNK)\n");
                    switch ($retcode) {
                        case -1:
                        case -3:
                            t_newtran();
                            t_on_failure("LAN2WAN");
                            t_reply("404", "Not Found");
                            exit;
                        case -2:
                            append_hf("Allow: INVITE, ACK, REFER, NOTIFY, CANCEL, BYE, REGISTER" );
                            sl_send_reply("405", "Method Not Allowed");
                            exit;
                    }
                }
                xdbg("Found to route $du TRUNK\n");

                setflag(487); /* Send 487 reply with route INBOUND_CALL_ACCESS_CONTROL, if failed */
                $avp(trunk_uuid) = $avp(TRUNK) ; 
                route(INBOUND_CALL_ACCESS_CONTROL); /* Check for call limitation */

                if(!has_totag()) {
                    $dlg_val(MediaProfileID) = $(avp(TRUNK){uri.param,MEDIA});
                    $dlg_val(from) = $fu ;
                    $dlg_val(request) = $ru ;
                    $dlg_val(channel) = "sip:" + $si + ":" + $sp;
                    $dlg_val(dchannel) = $du;
                    topology_hiding("C");
                    setflag(ACC_FLAG_CDR_FLAG);
                    setflag(ACC_FLAG_LOG_FLAG);
                    setflag(ACC_FLAG_DB_FLAG);
                    setflag(ACC_FLAG_FAILED_TRANSACTION);
                    append_hf("P-hint: tophide applied\r\n"); 
                    set_dlg_flag("DLG_FLAG_WAN2LAN") ;
                };
                $rd = $var(TRUNKIP);
                uac_replace_from("$avp(TRUNK)");

                t_on_failure("WAN2LAN");
                route(WAN2LAN);
                exit;
            }
            
            $avp(uuid) = "PBX:" + $avp(WAN) ;
            if(cache_fetch("local","$avp(uuid)",$avp(PBX))) {
                xdbg("Loaded from cache $avp(uuid): $avp(PBX)\n");
            } else if (avp_db_load("$avp(uuid)","$avp(PBX)/blox_config")) {
                cache_store("local","$avp(uuid)","$avp(PBX)");
                xdbg("Stored in cache $avp(uuid): $avp(PBX)\n");
            } else {
                $avp(PBX) = null;
            }
            if($avp(PBX)) {
                xdbg("Got from $Ri RE $avp(PBX)\n");
                #/* Check Roaming Extension routing */
                $var(PBXIP) = $(avp(PBX){uri.host}) ;
                $var(PBXPORT) = $(avp(PBX){uri.port}) ;
                $avp(LAN) = $(avp(PBX){uri.param,LAN});
                $avp(T38Param)  = $(avp(PBX){uri.param,T38Param});
                $avp(MEDIA)  = $(avp(PBX){uri.param,MEDIA});
                $avp(SrcSRTP) = $(avp(PBX){uri.param,WANSRTP});
                $avp(DstSRTP) = $(avp(PBX){uri.param,LANSRTP});

                if($avp(LAN)) {
                    if(cache_fetch("local","$avp(WAN)",$avp(WANProfile))) {
                        xdbg("Loaded from cache $avp(WAN): $avp(WANProfile)\n");
                    } else if (avp_db_load("$avp(WAN)","$avp(WANProfile)/blox_profile_config")) {
                        cache_store("local","$avp(WAN)","$avp(WANProfile)");
                        xdbg("Stored in cache $avp(WAN): $avp(WANProfile)\n");
                    }

                    $avp(WANADVIP) = $(avp(WANProfile){uri.param,advip});
                    if($avp(WANADVIP) == null || $avp(WANADVIP) == "") {#check for "" string not just null
                        $avp(WANSOCKET) = $pr + ":" + $Ri + ":" + $Rp ;
                    } else {
                        $avp(WANSOCKET) = $pr + ":" + $avp(WANADVIP) + ":" + $Rp ;
                    }

                    $avp(RESOCKET) = "sip:" + $si + ":" + $sp ;
                    ##$avp(RECHKONLYIP) = 1 ;
                    #if($avp(RECHKONLYIP)) { # /* Match only IP address in registrar not IP:PORT or PROTO */
                    #    $avp(RESOCKET) = $si ;
                    #}

                    if(cache_fetch("local","locationpbx:$fU:$avp(WANSOCKET):contact", $avp(contact)) \
                        && cache_fetch("local","locationpbx:$fU:$avp(WANSOCKET):received", $avp(received))) {
                        xdbg("locationpbx:$fU:$avp(WANSOCKET):contact => locationpbx:$fU:$avp(WANSOCKET):received => $avp(contact);$avp(received)") ;
                    } else if(avp_db_query("SELECT contact, received, TIMESTAMP(expires) FROM locationpbx WHERE username = '$fU' AND socket = '$avp(WANSOCKET)' ORDER BY last_modified DESC LIMIT 1", "$avp(contact);$avp(received);$avp(expires)")) {
                        xdbg("SELECT contact, received, TIMESTAMP(expires)-NOW() FROM locationpbx WHERE username = '$fU' AND socket = '$avp(WANSOCKET)' ORDER BY last_modified LIMIT 1, $avp(contact);$avp(received);$avp(expires)") ;
                        $var(expires) = ($avp(expires) - $Ts) * 1000;
                        #if($avp(RECHKONLYIP)) { # /* Match only IP address in registrar not IP:PORT or PROTO */
                        #    $avp(received) = $(avp(received){s.select,1,:}) ;
                        #}
                        cache_store("local","locationpbx:$fU:$avp(WANSOCKET):contact","$avp(contact)", $var(expires));
                        cache_store("local","locationpbx:$fU:$avp(WANSOCKET):received","$avp(received)", $var(expires));
                    } else {
                            xlog("L_INFO", "No Registration found try Re-Registering\n");
                            t_newtran();
                            t_on_failure("LAN2WAN");
                            t_reply("404", "Not Found");
                            exit;
                    }

                    if(!($avp(RESOCKET) == $avp(received))) { #We might be checking old cache, fix it now
                        xdbg("Not maching re-check DB $avp(RESOCKET) != $avp(received)\n");
                        if(avp_db_query("SELECT contact, received, TIMESTAMP(expires) FROM locationpbx WHERE username = '$fU' AND socket = '$avp(WANSOCKET)' ORDER BY last_modified LIMIT 1", "$avp(contact);$avp(received);$avp(expires)")) {
                            xdbg("SELECT contact, received, TIMESTAMP(expires)-NOW() FROM locationpbx WHERE username = '$fU' AND socket = '$avp(WANSOCKET)' ORDER BY last_modified LIMIT 1, $avp(contact);$avp(received);$avp(expires)") ;
                            $var(expires) = ($avp(expires) - $Ts) * 1000;
                            #if($avp(RECHKONLYIP)) { # /* Match only IP address in registrar not IP:PORT or PROTO */
                            #    $avp(received) = $(avp(received){s.select,1,:}) ;
                            #}
                            cache_store("local","locationpbx:$fU:$avp(WANSOCKET):contact","$avp(contact)", $var(expires));
                            cache_store("local","locationpbx:$fU:$avp(WANSOCKET):received","$avp(received)", $var(expires));
                        } else {
                            xlog("L_INFO", "No Registration found try Re-Registering\n");
                            t_newtran();
                            t_on_failure("LAN2WAN");
                            t_reply("404", "Not Found");
                            exit;
                        }
                    }

                    if($(avp(received){uri.param,transport})) {
                        if(!$(avp(RESOCKET){uri.param,transport})) { #/* If RESOCKET transport is empty */
                            $avp(RESOCKET) = $avp(RESOCKET) + ";transport=" + $(avp(received){uri.param,transport}) ;
                        }
                    }
                
                    if(!($avp(RESOCKET) == $avp(received))) {
                        xdbg("Not maching $avp(RESOCKET) != $avp(received)\n");
                        t_newtran();
                        t_on_failure("LAN2WAN");
                        t_reply("404", "Not Found");
                        exit;
                    }

                    if(cache_fetch("local","$avp(LAN)",$avp(LANProfile))) {
                        xdbg("Loaded from cache $avp(LAN): $avp(LANProfile)\n");
                    } else if (avp_db_load("$avp(LAN)","$avp(LANProfile)/blox_profile_config")) {
                        cache_store("local","$avp(LAN)","$avp(LANProfile)");
                        xdbg("Stored in cache $avp(LAN): $avp(LANProfile)\n");
                    } else {
                        $avp(LANProfile) = null;
                        xlog("L_INFO", "Drop MESSAGE $ru from $si : $sp\n" );
                        drop(); # /* Default 5060 open to accept packets from LAN side, but we don't process it */
                        exit;
                    }

                    #cache_store("local","LANProfile:$avp(LAN)","$avp(LANProfile)");
                    $avp(LANIP) = $(avp(LANProfile){uri.host});
                    $avp(LANPORT) = $(avp(LANProfile){uri.port});
                    $avp(LANPROTO) = $(avp(LANProfile){uri.param,transport});
                    if(!has_totag()) {
                        create_dialog("PpB");
                        $dlg_val(MediaProfileID) = $(avp(PBX){uri.param,MEDIA});
                        $dlg_val(from) = $fu ;
                        $dlg_val(request) = $ru ;
                        $dlg_val(channel) = "sip:" + $si + ":" + $sp;
                        $dlg_val(dchannel) = $avp(PBX);
                        topology_hiding("CR");
                        setflag(ACC_FLAG_CDR_FLAG);
                        setflag(ACC_FLAG_LOG_FLAG);
                        setflag(ACC_FLAG_DB_FLAG);
                        setflag(ACC_FLAG_FAILED_TRANSACTION);
                        append_hf("P-hint: tophide applied\r\n"); 
                        set_dlg_flag("DLG_FLAG_WAN2LAN") ;
                    }
                    $fs = $avp(LANPROTO) + ":" + $avp(LANIP) + ":" + $avp(LANPORT) ;
                    $du = $avp(PBX) + "transport=" + $avp(LANPROTO)  ;
                    $ru = "sip:" + $rU + "@" + $var(PBXIP) + ":" + $var(PBXPORT) ;
                    t_on_failure("WAN2LAN");
                    route(WAN2LAN);
                    exit;
                }
            }

            xlog("L_INFO", "Dropping SIP Method $rm received from $fu $si $sp to $ru ($avp(rcv))\n"); /* Dont know what to do */
            drop();
            exit;
        }
    }
}
