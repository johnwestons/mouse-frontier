"""The APK overlay must allow ENet and UDP discovery to open network sockets."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


class CoopAndroidManifestTests(unittest.TestCase):
    def test_local_play_network_permission_survives_manifest_merge(self):
        root = Path(__file__).resolve().parents[2]
        manifest = ET.parse(root / 'mobile/android/AndroidManifest.xml').getroot()
        android = '{http://schemas.android.com/apk/res/android}'
        tools = '{http://schemas.android.com/tools}'
        permissions = [item for item in manifest.findall('uses-permission')
                       if item.get(android + 'name') == 'android.permission.INTERNET']
        self.assertEqual(len(permissions), 1)
        self.assertNotEqual(permissions[0].get(tools + 'node'), 'remove')


if __name__ == '__main__':
    unittest.main()
