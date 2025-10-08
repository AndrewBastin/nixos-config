use anyhow::Result;
use clap::Parser;
use futures::{StreamExt, stream::{BoxStream, self}};
use serde::Serialize;
use zbus::{Connection, proxy, zvariant::OwnedObjectPath};

#[derive(Parser)]
#[command(name = "nm-status")]
#[command(about = "Monitor NetworkManager connection status", long_about = None)]
struct Cli {
    #[arg(short, long, help = "Print current status and exit (don't watch for changes)")]
    once: bool,
}

#[proxy(
    interface = "org.freedesktop.NetworkManager",
    default_service = "org.freedesktop.NetworkManager",
    default_path = "/org/freedesktop/NetworkManager"
)]
trait NetworkManager {
    #[zbus(property)]
    fn state(&self) -> zbus::Result<u32>;
    
    #[zbus(property)]
    fn connectivity(&self) -> zbus::Result<u32>;
    
    #[zbus(property)]
    fn primary_connection(&self) -> zbus::Result<OwnedObjectPath>;
}

#[proxy(
    interface = "org.freedesktop.NetworkManager.Connection.Active",
    default_service = "org.freedesktop.NetworkManager"
)]
trait ActiveConnection {
    #[zbus(property)]
    fn id(&self) -> zbus::Result<String>;
    
    #[zbus(property)]
    fn type_(&self) -> zbus::Result<String>;
    
    #[zbus(property)]
    fn state(&self) -> zbus::Result<u32>;
    
    #[zbus(property)]
    fn devices(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
}

#[proxy(
    interface = "org.freedesktop.NetworkManager.Device",
    default_service = "org.freedesktop.NetworkManager"
)]
trait Device {
    #[zbus(property)]
    fn interface(&self) -> zbus::Result<String>;
    
    #[zbus(property)]
    fn device_type(&self) -> zbus::Result<u32>;
}

#[proxy(
    interface = "org.freedesktop.NetworkManager.Device.Wireless",
    default_service = "org.freedesktop.NetworkManager"
)]
trait WirelessDevice {
    #[zbus(property)]
    fn active_access_point(&self) -> zbus::Result<OwnedObjectPath>;
}

#[proxy(
    interface = "org.freedesktop.NetworkManager.AccessPoint",
    default_service = "org.freedesktop.NetworkManager"
)]
trait AccessPoint {
    #[zbus(property)]
    fn strength(&self) -> zbus::Result<u8>;
}

#[derive(Serialize)]
struct NetworkStatus {
    has_internet: bool,
    connected: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    connection_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    interface: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    signal_strength: Option<u8>,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    let connection = Connection::system().await?;
    let nm_proxy = NetworkManagerProxy::new(&connection).await?;
    
    emit_status(&connection, &nm_proxy).await?;
    
    if cli.once {
        return Ok(());
    }
    
    let mut state_stream = nm_proxy.receive_state_changed().await;
    let mut connectivity_stream = nm_proxy.receive_connectivity_changed().await;
    let mut primary_conn_stream = nm_proxy.receive_primary_connection_changed().await;
    
    let mut signal_stream = get_signal_stream(&connection, &nm_proxy).await;
    
    loop {
        tokio::select! {
            Some(_) = state_stream.next() => {
                emit_status(&connection, &nm_proxy).await?;
                signal_stream = get_signal_stream(&connection, &nm_proxy).await;
            }
            Some(_) = connectivity_stream.next() => {
                emit_status(&connection, &nm_proxy).await?;
            }
            Some(_) = primary_conn_stream.next() => {
                emit_status(&connection, &nm_proxy).await?;
                signal_stream = get_signal_stream(&connection, &nm_proxy).await;
            }
            Some(_) = signal_stream.next() => {
                emit_status(&connection, &nm_proxy).await?;
            }
        }
    }
}

async fn get_signal_stream(connection: &Connection, nm_proxy: &NetworkManagerProxy<'_>) -> BoxStream<'static, zbus::proxy::PropertyChanged<'static, u8>> {
    match try_get_signal_stream(connection, nm_proxy).await {
        Ok(stream) => stream,
        Err(_) => stream::pending().boxed(),
    }
}

async fn try_get_signal_stream(connection: &Connection, nm_proxy: &NetworkManagerProxy<'_>) -> Result<BoxStream<'static, zbus::proxy::PropertyChanged<'static, u8>>> {
    let conn_path = nm_proxy.primary_connection().await?;
    if conn_path.as_str() == "/" {
        anyhow::bail!("No primary connection");
    }
    
    let conn_proxy = ActiveConnectionProxy::builder(connection)
        .path(conn_path)?
        .build()
        .await?;
    
    let devices = conn_proxy.devices().await?;
    let device_path = devices.first().ok_or_else(|| anyhow::anyhow!("No devices"))?.clone();
    
    let device_proxy = DeviceProxy::builder(connection)
        .path(device_path.clone())?
        .build()
        .await?;
    
    let device_type = device_proxy.device_type().await?;
    if device_type != 2 {
        anyhow::bail!("Not a wireless device");
    }
    
    let wireless_proxy = WirelessDeviceProxy::builder(connection)
        .path(device_path)?
        .build()
        .await?;
    
    let ap_path = wireless_proxy.active_access_point().await?;
    if ap_path.as_str() == "/" {
        anyhow::bail!("No active access point");
    }
    
    let ap_proxy = AccessPointProxy::builder(connection)
        .path(ap_path)?
        .build()
        .await?;
    
    Ok(ap_proxy.receive_strength_changed().await.boxed())
}

async fn emit_status(connection: &Connection, nm_proxy: &NetworkManagerProxy<'_>) -> Result<()> {
    let state = nm_proxy.state().await?;
    let connectivity = nm_proxy.connectivity().await?;
    let primary_conn_path = nm_proxy.primary_connection().await?;
    
    let has_internet = connectivity == 4;
    let state_connected = state >= 50 && state <= 70;
    
    let (connection_name, interface, signal_strength, connection_type) = 
        get_connection_details(connection, &primary_conn_path, state_connected).await;
    
    let connected = state_connected && connection_type.as_ref().map_or(false, |t| {
        t == "802-3-ethernet" || t == "802-11-wireless"
    });
    
    let status = NetworkStatus {
        has_internet,
        connected,
        connection_name,
        interface,
        signal_strength,
    };
    
    println!("{}", serde_json::to_string(&status)?);
    
    Ok(())
}

async fn get_connection_details(
    connection: &Connection,
    conn_path: &OwnedObjectPath,
    connected: bool,
) -> (Option<String>, Option<String>, Option<u8>, Option<String>) {
    if conn_path.as_str() == "/" || !connected {
        return (None, None, None, None);
    }
    
    let conn_proxy = match ActiveConnectionProxy::builder(connection)
        .path(conn_path)
        .map(|b| b.build())
    {
        Ok(fut) => match fut.await {
            Ok(proxy) => proxy,
            Err(_) => return (None, None, None, None),
        },
        Err(_) => return (None, None, None, None),
    };
    
    let name = conn_proxy.id().await.ok();
    let conn_type = conn_proxy.type_().await.ok();
    let conn_state = conn_proxy.state().await.unwrap_or(0);
    
    if conn_state != 2 {
        return (None, None, None, None);
    }
    
    let Ok(devices) = conn_proxy.devices().await else {
        return (name, None, None, conn_type);
    };
    
    let Some(device_path) = devices.first() else {
        return (name, None, None, conn_type);
    };
    
    let (interface, signal_strength) = get_device_details(connection, device_path).await;
    (name, interface, signal_strength, conn_type)
}

async fn get_device_details(connection: &Connection, device_path: &OwnedObjectPath) -> (Option<String>, Option<u8>) {
    let device_proxy = match DeviceProxy::builder(connection)
        .path(device_path)
        .map(|b| b.build())
    {
        Ok(fut) => match fut.await {
            Ok(proxy) => proxy,
            Err(_) => return (None, None),
        },
        Err(_) => return (None, None),
    };
    
    let interface = device_proxy.interface().await.ok();
    let device_type = device_proxy.device_type().await.unwrap_or(0);
    
    let signal_strength = if device_type == 2 {
        get_wifi_signal_strength(connection, device_path).await
    } else {
        None
    };
    
    (interface, signal_strength)
}

async fn get_wifi_signal_strength(connection: &Connection, device_path: &OwnedObjectPath) -> Option<u8> {
    let wireless_proxy = WirelessDeviceProxy::builder(connection)
        .path(device_path)
        .ok()?
        .build()
        .await
        .ok()?;
    
    let ap_path = wireless_proxy.active_access_point().await.ok()?;
    if ap_path.as_str() == "/" {
        return None;
    }
    
    let ap_proxy = AccessPointProxy::builder(connection)
        .path(&ap_path)
        .ok()?
        .build()
        .await
        .ok()?;
    
    ap_proxy.strength().await.ok()
}


