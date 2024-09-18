import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MaterialApp(home: BluetoothPrinter(text: "........", styles: PosStyles())));

class BluetoothPrinter extends StatefulWidget {
  final String text;
  final PosStyles styles;
  const BluetoothPrinter({super.key, required this.text, required this.styles});

  @override
  State<BluetoothPrinter> createState() => _BluetoothPrinterState();
}

class _BluetoothPrinterState extends State<BluetoothPrinter> {
  List<BluetoothDevice> devicesList = [];
  List<BluetoothDevice> saveDevicesList = [];
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? writeCharacteristic;
  SharedPreferences? prefs;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    loadDevices();
  }

  Future<void> scanDevices() async
  {
    setState(() {
      loading = true;
    });
    if (await Permission.bluetoothScan.isDenied || await Permission.bluetoothConnect.isDenied)
    {
      await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location,].request();
    }
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    await FlutterBluePlus.scanResults.listen((results)
    {
      for (ScanResult r in results)
      {
        if (!devicesList.contains(r.device))
        {
          setState(() {
            devicesList.add(r.device);
          });
        }
      }
    });
    setState(() {
      loading = false;
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async
  {
    await device.connect();
    setState(() {
      connectedDevice = device;
    });
    List<BluetoothService> services = await device.discoverServices();
    for (var service in services)
    {
      for (var characteristic in service.characteristics) {
        if (characteristic.properties.write) {
          setState(() {
            writeCharacteristic = characteristic;
          });
        }
      }
    }
    await saveDevice(device);
  }

  Future<void> printText(BluetoothDevice device) async
  {
    await connectToDevice(device);
    try
    {
      if (writeCharacteristic != null && connectedDevice != null)
      {
        final profile = await CapabilityProfile.load();
        final generator = Generator(PaperSize.mm80, profile);
        final List<int> bytes = generator.text(widget.text, styles: widget.styles);
        await writeCharacteristic!.write(bytes);
      }
      else
      {
        throw("writeCharacteristic or connectedDevice null");
      }
    } catch (e) {
      throw("$e");
    }
  }

  Future<void> saveDevice(BluetoothDevice device) async
  {
    List<String>? prefsList = prefs?.getStringList("devices");
    if(prefsList!=null && !(prefsList.contains(device.remoteId.toString())))
    {
      prefsList.add(device.remoteId.toString());
    }
    prefs?.setStringList('devices', prefsList??[device.remoteId.toString()]);
    await loadDevices();
  }

  Future<void> removeDevice(BluetoothDevice device) async
  {
    List<String>? prefsList = prefs?.getStringList("devices");
    if(prefsList!=null && prefsList.contains(device.remoteId.toString()))
    {
      prefsList.remove(device.remoteId.toString());
      saveDevicesList.remove(device);
    }
    prefs?.setStringList('devices', prefsList??[]);
    await loadDevices();
  }

  Future<void> loadDevices() async
  {
    prefs = await SharedPreferences.getInstance();
    List<String>? prefsList = prefs?.getStringList("devices");
    setState(() {
      if(prefsList != null)
      {
        saveDevicesList = prefsList.map((e) => BluetoothDevice.fromId(e)).toList();
      }
    });
    scanDevices();
  }

  @override
  Widget build(BuildContext context) {
    bool unknown = false;

    SizedBox loadingIcon = const SizedBox(width: 20,height: 20, child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(
        title: const Text("Kayıtlı Bluetooth Cihazları"),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
          icon: loading
              ? loadingIcon
              : const Icon(Icons.adf_scanner_rounded),
          label: const Text("Yeni Cihaz Ekle"),
          onPressed: () async
          {
            await scanDevices();
            await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (BuildContext context) => StatefulBuilder(
                  builder: (context,set) {
                    return Container(
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(25),
                          topRight: Radius.circular(25),
                        ),
                      ),
                      padding: const EdgeInsets.all(15),
                      width: double.infinity,
                      height: MediaQuery.sizeOf(context).height/3*2,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text("Cihaz Ekle",style: TextStyle(fontSize: 20,fontWeight: FontWeight.bold)),
                                    IconButton(onPressed: () async
                                    {
                                      setState(() {
                                        set(() {
                                          loading = true;
                                        });
                                      });
                                      await scanDevices();
                                      await Future.delayed(const Duration(seconds: 1));
                                      setState(() {
                                        set(() {
                                          loading = false;
                                          devicesList;
                                        });
                                      });
                                    },
                                        icon: loading ? loadingIcon : const Icon(Icons.refresh_rounded)
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const Text("Diğer Cihazlar",style: TextStyle(fontSize: 17)),
                                    const SizedBox(width:5),
                                    Switch(value: unknown, onChanged: (v) {set((){unknown = v;});}),
                                  ],
                                )
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: devicesList.length,
                              itemBuilder: (context, index)
                              {
                                BluetoothDevice device = devicesList[index];
                                String deviceName = device.platformName;
                                return (!unknown && deviceName.isEmpty)
                                    ? Container()
                                    : ListTile(
                                  title: Text(deviceName.isNotEmpty ? deviceName : device.remoteId.toString()),
                                  onTap: () async {connectToDevice(device);Navigator.pop(context);},
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  }
              ),
            );
          }
      ),
      body: saveDevicesList.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: loadDevices,
        child: ListView.builder(
            itemCount: saveDevicesList.length,
            itemBuilder: (context, index) {
              BluetoothDevice device = saveDevicesList[index];
              return ListTile(
                title: Text(device.platformName.isNotEmpty ? device.platformName : device.remoteId.toString()),
                onTap: () async => await printText(device),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red,),
                  onPressed: () async => await removeDevice(device),
                ),
              );}),
      ),
    );
  }
}