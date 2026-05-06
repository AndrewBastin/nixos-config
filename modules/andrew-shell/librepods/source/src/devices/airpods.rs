use crate::bluetooth::aacp::ControlCommandIdentifiers;
use crate::bluetooth::aacp::{AACPEvent, AACPManager, AirPodsLEKeys, ProximityKeyType};
use crate::media_controller::MediaController;
use bluer::Address;
use log::{debug, error, info};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio::time::{Duration, sleep};
use crate::utils::get_app_settings_path;

pub struct AirPodsDevice {
    pub mac_address: Address,
    pub aacp_manager: AACPManager,
    pub media_controller: Arc<Mutex<MediaController>>,
}

impl AirPodsDevice {
    pub async fn new(mac_address: Address) -> Self {
        info!("Creating new AirPodsDevice for {}", mac_address);
        let mut aacp_manager = AACPManager::new();
        aacp_manager.connect(mac_address).await;

        info!("Sending handshake");
        if let Err(e) = aacp_manager.send_handshake().await {
            error!("Failed to send handshake to AirPods device: {}", e);
        }

        sleep(Duration::from_millis(300)).await;

        info!("Setting feature flags");
        if let Err(e) = aacp_manager.send_set_feature_flags_packet().await {
            error!("Failed to set feature flags: {}", e);
        }

        sleep(Duration::from_millis(300)).await;

        info!("Requesting notifications");
        if let Err(e) = aacp_manager.send_notification_request().await {
            error!("Failed to request notifications: {}", e);
        }

        info!("sending some packet");
        if let Err(e) = aacp_manager.send_some_packet().await {
            error!("Failed to send some packet: {}", e);
        }

        info!("Requesting Proximity Keys: IRK and ENC_KEY");
        if let Err(e) = aacp_manager
            .send_proximity_keys_request(vec![ProximityKeyType::Irk, ProximityKeyType::EncKey])
            .await
        {
            error!("Failed to request proximity keys: {}", e);
        }

        let app_settings_path = get_app_settings_path();
        let settings = std::fs::read_to_string(&app_settings_path)
            .ok()
            .and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok());
        let stem_control = settings
            .clone()
            .and_then(|v| v.get("stem_control").cloned())
            .and_then(|s| serde_json::from_value(s).ok())
            .unwrap_or(false);

        if stem_control {
            // Enable stem press detection (double and triple tap)
            // StemConfig bitmask for the control command: single=0x01, double=0x02, triple=0x04, long=0x08
            // We want double and triple: 0x02 | 0x04 = 0x06
            info!("Enabling stem press detection for double and triple tap");
            if let Err(e) = aacp_manager
                .send_control_command(ControlCommandIdentifiers::StemConfig, &[0x06])
                .await
            {
                error!("Failed to enable stem press detection: {}", e);
            }
        }

        let session = bluer::Session::new()
            .await
            .expect("Failed to get bluer session");
        let adapter = session
            .default_adapter()
            .await
            .expect("Failed to get default adapter");
        let local_mac = adapter
            .address()
            .await
            .expect("Failed to get adapter address")
            .to_string();

        let media_controller = Arc::new(Mutex::new(MediaController::new(
            mac_address.to_string(),
            local_mac.clone(),
        )));
        let mc_clone = media_controller.clone();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let (command_tx, mut command_rx) = tokio::sync::mpsc::unbounded_channel();

        aacp_manager.set_event_channel(tx).await;

        // Publish handles into the IPC bus so external clients (CLI,
        // Quickshell) can drive control commands and the take-back sequence.
        {
            let bus = crate::ipc::bus();
            *bus.aacp_manager.lock().await = Some(aacp_manager.clone());
            *bus.command_tx.lock().await = Some(command_tx.clone());
            *bus.media_controller.lock().await = Some(media_controller.clone());
            let mac_str = mac_address.to_string();
            bus.update(|s| {
                s.connected = true;
                s.mac = Some(mac_str);
                // Name is filled in by main.rs since it has the BlueZ-resolved
                // friendly name; we only know the MAC here.
            })
            .await;
        }

        let aacp_manager_clone = aacp_manager.clone();
        tokio::spawn(async move {
            while let Some((id, value)) = command_rx.recv().await {
                if let Err(e) = aacp_manager_clone.send_control_command(id, &value).await {
                    log::error!("Failed to send control command: {}", e);
                }
            }
        });

        let mc_listener = media_controller.lock().await;
        let aacp_manager_clone_listener = aacp_manager.clone();
        mc_listener
            .start_playback_listener(aacp_manager_clone_listener, command_tx.clone())
            .await;
        drop(mc_listener);

        let (listening_mode_tx, mut listening_mode_rx) = tokio::sync::mpsc::unbounded_channel();
        aacp_manager
            .subscribe_to_control_command(
                ControlCommandIdentifiers::ListeningMode,
                listening_mode_tx,
            )
            .await;
        tokio::spawn(async move {
            while let Some(value) = listening_mode_rx.recv().await {
                let raw = value[0];
                let mode = match raw {
                    0x01 => Some("off"),
                    0x02 => Some("anc"),
                    0x03 => Some("transparency"),
                    0x04 => Some("adaptive"),
                    _ => None,
                };
                if let Some(m) = mode {
                    crate::ipc::bus()
                        .update(|s| s.mode = Some(m.to_string()))
                        .await;
                }
            }
        });

        let (allow_off_tx, mut allow_off_rx) = tokio::sync::mpsc::unbounded_channel();
        aacp_manager
            .subscribe_to_control_command(ControlCommandIdentifiers::AllowOffOption, allow_off_tx)
            .await;
        tokio::spawn(async move {
            while let Some(_value) = allow_off_rx.recv().await {
                // allow_off is consumed by the tray which no longer exists;
                // kept subscribed so the AACP manager does not back-pressure.
            }
        });

        let (conversation_detect_tx, mut conversation_detect_rx) =
            tokio::sync::mpsc::unbounded_channel();
        aacp_manager
            .subscribe_to_control_command(
                ControlCommandIdentifiers::ConversationDetectConfig,
                conversation_detect_tx,
            )
            .await;
        tokio::spawn(async move {
            while let Some(value) = conversation_detect_rx.recv().await {
                let enabled = value[0] == 0x01;
                crate::ipc::bus()
                    .update(|s| s.conversational_awareness = enabled)
                    .await;
            }
        });

        let (owns_connection_tx, mut owns_connection_rx) = tokio::sync::mpsc::unbounded_channel();
        aacp_manager
            .subscribe_to_control_command(
                ControlCommandIdentifiers::OwnsConnection,
                owns_connection_tx,
            )
            .await;
        let mc_clone_owns = media_controller.clone();
        tokio::spawn(async move {
            while let Some(value) = owns_connection_rx.recv().await {
                let owns = value.first().copied().unwrap_or(0) != 0;
                crate::ipc::bus().update(|s| s.owns = owns).await;
                if !owns {
                    info!("Lost ownership, pausing media and disconnecting audio");
                    let controller = mc_clone_owns.lock().await;
                    controller.pause_all_media().await;
                    controller.deactivate_a2dp_profile().await;
                }
            }
        });

        let aacp_manager_clone_events = aacp_manager.clone();
        let local_mac_events = local_mac.clone();
        let command_tx_clone = command_tx.clone();
        tokio::spawn(async move {
            // Track the most recent AudioSource type the firmware reported for
            // *fern's* MAC. We use the Media -> None transition as the cleanest
            // signal that the AirPods routed audio away from us — far more
            // reliable than the OwnsConnection control command (which the
            // firmware does not always send) or the OwnershipToFalseRequest
            // plist (which only fires on explicit banner taps).
            let mut prev_local_audio_type: Option<crate::bluetooth::aacp::AudioSourceType> = None;
            while let Some(event) = rx.recv().await {
                match event {
                    AACPEvent::EarDetection(old_status, new_status) => {
                        debug!(
                            "Received EarDetection event: old_status={:?}, new_status={:?}",
                            old_status, new_status
                        );
                        let in_ear_vec: Vec<bool> = new_status
                            .iter()
                            .map(|s| {
                                matches!(s, crate::bluetooth::aacp::EarDetectionStatus::InEar)
                            })
                            .collect();
                        crate::ipc::bus().update(|s| s.in_ear = in_ear_vec).await;
                        let controller = mc_clone.lock().await;
                        debug!(
                            "Calling handle_ear_detection with old_status: {:?}, new_status: {:?}",
                            old_status, new_status
                        );
                        controller
                            .handle_ear_detection(old_status, new_status)
                            .await;
                    }
                    AACPEvent::BatteryInfo(battery_info) => {
                        debug!("Received BatteryInfo event: {:?}", battery_info);
                        // Headphone (component 0x01) is the primary battery for
                        // AirPods Max. For in-ear models, fall back to whichever
                        // bud reports lowest as a "worst-case" headline value.
                        let battery_level = battery_info
                            .iter()
                            .find(|b| b.component as u8 == 0x01)
                            .map(|b| b.level)
                            .or_else(|| {
                                battery_info
                                    .iter()
                                    .filter(|b| matches!(b.component as u8, 0x02 | 0x04))
                                    .map(|b| b.level)
                                    .min()
                            });
                        crate::ipc::bus()
                            .update(|s| s.battery = battery_level)
                            .await;
                    }
                    AACPEvent::ControlCommand(status) => {
                        debug!("Received ControlCommand event: {:?}", status);
                    }
                    AACPEvent::ConversationalAwareness(status) => {
                        debug!("Received ConversationalAwareness event: {}", status);
                        let controller = mc_clone.lock().await;
                        controller.handle_conversational_awareness(status).await;
                    }
                    AACPEvent::ConnectedDevices(old_devices, new_devices) => {
                        let local_mac = local_mac_events.clone();

                        // Publish the peer list (excluding ourselves) into the
                        // IPC snapshot so external clients can see who else is
                        // connected. info2 bit 2 (0x04) appears to indicate
                        // "owns audio" based on observed values.
                        let peers: Vec<crate::ipc::PeerInfo> = {
                            let manager_state = aacp_manager_clone_events.state.lock().await;
                            new_devices
                                .iter()
                                .filter(|d| d.mac != local_mac)
                                .map(|d| crate::ipc::PeerInfo {
                                    mac: d.mac.clone(),
                                    name: manager_state.peer_names.get(&d.mac).cloned(),
                                    owns: (d.info2 & 0x04) != 0,
                                })
                                .collect()
                        };
                        crate::ipc::bus().update(|s| s.peers = peers).await;

                        let new_devices_filtered = new_devices.iter().filter(|new_device| {
                            let not_in_old = old_devices
                                .iter()
                                .all(|old_device| old_device.mac != new_device.mac);
                            let not_local = new_device.mac != local_mac;
                            not_in_old && not_local
                        });

                        for device in new_devices_filtered {
                            info!(
                                "New connected device: {}, info1: {}, info2: {}",
                                device.mac, device.info1, device.info2
                            );
                            info!(
                                "Sending new Tipi packet for device {}, and sending media info to the device",
                                device.mac
                            );
                            let aacp_manager_clone = aacp_manager_clone_events.clone();
                            let local_mac_clone = local_mac.clone();
                            let device_mac_clone = device.mac.clone();
                            tokio::spawn(async move {
                                if let Err(e) = aacp_manager_clone
                                    .send_media_information_new_device(
                                        &local_mac_clone,
                                        &device_mac_clone,
                                    )
                                    .await
                                {
                                    error!("Failed to send media info new device: {}", e);
                                }
                                if let Err(e) = aacp_manager_clone
                                    .send_add_tipi_device(&local_mac_clone, &device_mac_clone)
                                    .await
                                {
                                    error!("Failed to send add tipi device: {}", e);
                                }
                            });
                        }
                    }
                    AACPEvent::OwnershipToFalseRequest => {
                        info!(
                            "Received ownership to false request. Setting ownership to false and pausing media."
                        );
                        let _ = command_tx_clone
                            .send((ControlCommandIdentifiers::OwnsConnection, vec![0x00]));
                        let controller = mc_clone.lock().await;
                        controller.pause_all_media().await;
                        controller.deactivate_a2dp_profile().await;
                    }
                    AACPEvent::AudioSource(ref audio_source)
                        if audio_source.mac == local_mac_events =>
                    {
                        use crate::bluetooth::aacp::AudioSourceType;
                        let new_type = audio_source.r#type;
                        let was_active = matches!(
                            prev_local_audio_type,
                            Some(AudioSourceType::Media | AudioSourceType::Call)
                        );
                        let is_active = matches!(
                            new_type,
                            AudioSourceType::Media | AudioSourceType::Call
                        );
                        prev_local_audio_type = Some(new_type);
                        if !(was_active && !is_active) {
                            // First observation, no transition, or transition
                            // into Media/Call — nothing to do.
                            continue;
                        }

                        info!(
                            "Audio routed away from this host (Media/Call -> None); debouncing before offering take-back"
                        );

                        let aacp_for_action = aacp_manager_clone_events.clone();
                        let local_mac_for_action = local_mac_events.clone();
                        let mc_for_action = mc_clone.clone();
                        let command_tx_for_action = command_tx_clone.clone();
                        tokio::spawn(async move {
                            // iPhone notification dings briefly steal audio
                            // (Media/Call -> None -> Media within ~1s), which
                            // would otherwise pop a take-back notification per
                            // ding. Wait, then re-check state: if local audio
                            // is back, the away was transient and we bail.
                            const TAKEBACK_DEBOUNCE: Duration = Duration::from_millis(2500);
                            sleep(TAKEBACK_DEBOUNCE).await;

                            let (target_mac, target_name) = {
                                use crate::bluetooth::aacp::AudioSourceType;
                                let state = aacp_for_action.state.lock().await;
                                let still_away = match &state.audio_source {
                                    Some(src) => !(src.mac == local_mac_for_action
                                        && matches!(
                                            src.r#type,
                                            AudioSourceType::Media | AudioSourceType::Call
                                        )),
                                    None => true,
                                };
                                if !still_away {
                                    debug!(
                                        "Audio returned to this host within debounce window; skipping take-back notification"
                                    );
                                    return;
                                }
                                let mac = state
                                    .connected_devices
                                    .iter()
                                    .find(|d| d.mac != local_mac_for_action)
                                    .map(|d| d.mac.clone());
                                let name = mac
                                    .as_ref()
                                    .and_then(|m| state.peer_names.get(m).cloned());
                                (mac, name)
                            };
                            let Some(target_mac) = target_mac else {
                                debug!(
                                    "No non-self peer in connected_devices; skipping take-back notification"
                                );
                                return;
                            };
                            let display = target_name.unwrap_or_else(|| target_mac.clone());

                            let body = format!("Audio moved to {}. Take it back?", display);
                            let clicked = tokio::task::spawn_blocking(move || {
                                use notify_rust::{Notification, Timeout};
                                let handle = match Notification::new()
                                    .summary("AirPods routed elsewhere")
                                    .body(&body)
                                    .action("take_back", "Take back")
                                    .timeout(Timeout::Milliseconds(15000))
                                    .show()
                                {
                                    Ok(h) => h,
                                    Err(e) => {
                                        log::warn!(
                                            "Failed to show take-back notification: {}",
                                            e
                                        );
                                        return false;
                                    }
                                };
                                let mut clicked = false;
                                handle.wait_for_action(|action| {
                                    if action == "take_back" {
                                        clicked = true;
                                    }
                                });
                                clicked
                            })
                            .await
                            .unwrap_or(false);

                            if !clicked {
                                debug!("Take-back notification dismissed without action");
                                return;
                            }

                            info!(
                                "User requested take-back; firing takeover sequence to {}",
                                target_mac
                            );
                            let _ = command_tx_for_action.send((
                                ControlCommandIdentifiers::OwnsConnection,
                                vec![0x01],
                            ));
                            {
                                let controller = mc_for_action.lock().await;
                                controller.activate_a2dp_profile().await;
                            }
                            if let Err(e) = aacp_for_action
                                .send_media_information(
                                    &local_mac_for_action,
                                    &target_mac,
                                    true,
                                )
                                .await
                            {
                                error!("Failed to send media information: {}", e);
                            }
                            if let Err(e) = aacp_for_action
                                .send_smart_routing_show_ui(&target_mac)
                                .await
                            {
                                error!("Failed to send smart routing show ui: {}", e);
                            }
                            if let Err(e) =
                                aacp_for_action.send_hijack_request(&target_mac).await
                            {
                                error!("Failed to send hijack request: {}", e);
                            }
                        });
                    }
                    AACPEvent::StemPress(press_type, bud_type) => {
                        use crate::bluetooth::aacp::StemPressType;
                        info!(
                            "Received Stem Press: {:?} on {:?}",
                            press_type, bud_type
                        );
                        if stem_control {
                            let controller = mc_clone.lock().await;
                            match press_type {
                                StemPressType::DoublePress => {
                                    info!("Double press detected, skipping to next track");
                                    controller.next_track().await;
                                }
                                StemPressType::TriplePress => {
                                    info!("Triple press detected, going to previous track");
                                    controller.previous_track().await;
                                }
                                _ => {
                                    debug!("Unhandled stem press type: {:?}", press_type);
                                }
                            }
                        } else {
                            debug!("Stem control disabled, ignoring stem press event");
                        }
                    }
                    _ => {
                        debug!("Received unhandled AACP event: {:?}", event);
                    }
                }
            }
        });

        AirPodsDevice {
            mac_address,
            aacp_manager,
            media_controller,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AirPodsInformation {
    pub name: String,
    pub model_number: String,
    pub manufacturer: String,
    pub serial_number: String,
    pub version1: String,
    pub version2: String,
    pub hardware_revision: String,
    pub updater_identifier: String,
    pub left_serial_number: String,
    pub right_serial_number: String,
    pub version3: String,
    pub le_keys: AirPodsLEKeys,
}
