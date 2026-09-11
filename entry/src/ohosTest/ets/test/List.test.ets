/**
 * List.test.ets —— ohosTest 用例总入口。
 */

import connectionTest from './Connection.test';
import trajectoryProjectionTest from './Trajectory.test';
import settingsProjectionTest from './Settings.test';
import muxProbeTest from './MuxProbe.test';

export default function testsuite() {
  connectionTest();
  trajectoryProjectionTest();
  settingsProjectionTest();
  muxProbeTest();
}
