/**
 * List.test.ets —— ohosTest 用例总入口。
 */

import connectionTest from './Connection.test';
import trajectoryProjectionTest from './Trajectory.test';

export default function testsuite() {
  connectionTest();
  trajectoryProjectionTest();
}
