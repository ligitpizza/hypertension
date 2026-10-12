import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/api_providers.dart';
import '../data/ppg_capture.dart';
import '../data/vitals_repository.dart';

final vitalsRepositoryProvider = Provider<VitalsRepository>(
  (ref) => ApiVitalsRepository(ref.watch(apiClientProvider)),
);

final ppgCaptureProvider = Provider<PpgCapture>((ref) => CameraPpgCapture());
