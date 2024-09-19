import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MaterialApp(home: BluetoothPrinter(text: "vcsdkjvbdskjvbdskjvbjds")));

class BluetoothPrinter extends StatefulWidget {
  final String text;
  const BluetoothPrinter({super.key, required this.text});

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
  bool miniLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      loadDevices();
    });
  }

  Future<void> scanDevices() async
  {
    setState(() {
      miniLoading = true;
    });
    if (await Permission.bluetoothScan.isDenied || await Permission.bluetoothConnect.isDenied)
    {
      await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location,].request();
    }
    if(!(await FlutterBluePlus.isOn))
    {
      //showToast("Lütfen bluetoothu açın", "Red", false);
    }
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results)
    {
      for (ScanResult r in results)
      {
        if (!devicesList.contains(r.device))
        {
          mounted
              ? setState(() {
            devicesList.add(r.device);
          })
              : devicesList.add(r.device);
        }
      }
    });
    setState(() {
      miniLoading = false;
    });
  }

  Future<void> connectToDevice(BluetoothDevice device, bool back) async {
    if(!miniLoading)
    {
      setState(() {
        miniLoading = true;
      });
      try {
        await device.connect();
        setState(() => connectedDevice = device);
        List<BluetoothService> services = await device.discoverServices();
        writeCharacteristic = services
            .expand((service) => service.characteristics)
            .firstWhere(
              (characteristic) => characteristic.properties.write,
          orElse: () => throw Exception("Yazma desteği olan bir karakteristik bulunamadı."),
        );
        await saveDevice(device);
      } catch (e) {
        //showToast("Bağlantı hatası: ${e.toString()}", "Red", true);
      }
      setState(() {
        miniLoading = false;
      });
      if(back)
      {
        Navigator.pop(context);
      }
    }
  }

  Future<void> printText(BluetoothDevice device) async {
    if(!loading)
    {
      setState(() {
        loading = true;
      });
      try {
        await connectToDevice(device,false);
        if (writeCharacteristic != null && connectedDevice != null)
        {
          final profile = await CapabilityProfile.load();
          final generator = Generator(PaperSize.mm58, profile);
          final List<int> bytes = generator.text(widget.text, styles: PosStyles(align: PosAlign.center));
          const int chunkSize = 237;
          for (int i = 0; i < bytes.length; i += chunkSize)
          {
            List<int> chunk = bytes.sublist(i, i + chunkSize > bytes.length ? bytes.length : i + chunkSize);
            await writeCharacteristic!.write(chunk).timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw ("Veri yazma işlemi 10 saniye geçtiği için zaman aşımına uğradı.");
              },
            );
          }
          Navigator.pop(context);
        } else {
          throw ("Bağlı veya yapılandırılmış cihaz yok.");
        }
      } catch (e) {
        //showToast("Yazdırma Hatası: ${e.toString()}","Red", true);
        throw ("$e");
      }
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> saveDevice(BluetoothDevice device) async
  {
    List<String>? prefsList = prefs?.getStringList("bluetoothDevices");
    if(prefsList!=null && !(prefsList.contains(device.remoteId.toString())))
    {
      prefsList.add(device.remoteId.toString());
    }
    prefs?.setStringList("bluetoothDevices", prefsList??[device.remoteId.toString()]);
    await loadDevices();
  }

  Future<void> removeDevice(BluetoothDevice device) async
  {
    List<String>? prefsList = prefs?.getStringList("bluetoothDevices");
    if(prefsList!=null && prefsList.contains(device.remoteId.toString()))
    {
      prefsList.remove(device.remoteId.toString());
      saveDevicesList.remove(device);
    }
    prefs?.setStringList("bluetoothDevices", prefsList??[]);
    await loadDevices();
  }

  Future<void> loadDevices() async
  {
    setState(() {
      loading = true;
    });
    prefs = await SharedPreferences.getInstance();
    List<String>? prefsList = prefs?.getStringList("bluetoothDevices");
    setState(() {
      if(prefsList != null)
      {
        saveDevicesList = prefsList.map((e) => BluetoothDevice(remoteId: DeviceIdentifier(e))).toList();
      }
    });
    setState(() {
      loading = false;
    });
    scanDevices();
  }

  @override
  Widget build(BuildContext context) {
    bool unknown = false;

    SizedBox loadingIcon = SizedBox(width: 20,height: 20, child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(
        title: const Text("Kayıtlı Bluetooth Cihazları"),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
          icon: miniLoading
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
                                          miniLoading = true;
                                        });
                                      });
                                      await scanDevices();
                                      await Future.delayed(const Duration(seconds: 1));
                                      setState(() {
                                        set(() {
                                          miniLoading = false;
                                          devicesList;
                                        });
                                      });
                                    },
                                        icon: miniLoading ? loadingIcon : Icon(Icons.refresh_rounded)
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
                                  onTap: () async => connectToDevice(device,true),
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
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : saveDevicesList.isEmpty ? Center(child: Text("Hiç kayıtlı yazıcı yok."),) :
      RefreshIndicator(
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