type AdapterConfiguration = {
  endpoint?: string;
  debounceMs?: number;
};

type Subscription = { unsubscribe?: () => void } | (() => void) | undefined;

/**
 * Consome, sem modificar, o MeasurementService nativo do OHIF.
 *
 * A credencial é recebida no fragmento da URL, removida imediatamente e usada
 * somente como bearer token para postar snapshots serializáveis no VOXEL PACS.
 */
export default class VoxelMeasurementAdapterService {
  public static readonly REGISTRATION = {
    name: 'voxelMeasurementAdapterService',
    altName: 'VoxelMeasurementAdapterService',
    create: ({ configuration = {} }) => new VoxelMeasurementAdapterService(configuration),
  };

  private configuration: AdapterConfiguration;
  private subscriptions: Subscription[] = [];
  private pending = new Map<string, { action: 'upsert' | 'remove'; measurement: any }>();
  private flushTimer?: number;
  private endpoint?: string;
  private bearerToken?: string;
  private studyInstanceUid?: string;

  constructor(configuration: AdapterConfiguration = {}) {
    this.configuration = configuration;
  }

  public onModeEnter({ servicesManager, extensionManager }): void {
    this.onModeExit();

    const config = (window as any).config?.voxelMeasurementAdapter || this.configuration;
    this.endpoint = config?.endpoint;
    this.bearerToken = this.consumeTokenFromFragment();
    this.studyInstanceUid = this.getStudyInstanceUid();

    if (!this.endpoint || !this.bearerToken || !this.studyInstanceUid) {
      return;
    }

    const { measurementService } = servicesManager.services;
    if (!measurementService) {
      return;
    }

    const events = measurementService.EVENTS;
    this.subscriptions = [
      measurementService.subscribe(events.MEASUREMENT_ADDED, ({ measurement }) =>
        this.queue('upsert', measurement)
      ),
      measurementService.subscribe(events.MEASUREMENT_UPDATED, ({ measurement }) =>
        this.queue('upsert', measurement)
      ),
      measurementService.subscribe(events.RAW_MEASUREMENT_ADDED, ({ measurement }) =>
        this.queue('upsert', measurement)
      ),
      measurementService.subscribe(events.MEASUREMENT_REMOVED, ({ measurement }) =>
        this.queue('remove', { uid: measurement })
      ),
      measurementService.subscribe(events.MEASUREMENTS_CLEARED, ({ measurements }) => {
        (measurements || []).forEach(measurement => this.queue('remove', { uid: measurement?.uid }));
      }),
    ];

    measurementService.getMeasurements().forEach(measurement => this.queue('upsert', measurement));
  }

  public onModeExit(): void {
    this.subscriptions.forEach(subscription => {
      if (typeof subscription === 'function') {
        subscription();
      } else {
        subscription?.unsubscribe?.();
      }
    });
    this.subscriptions = [];
    this.pending.clear();
    if (this.flushTimer) {
      window.clearTimeout(this.flushTimer);
      this.flushTimer = undefined;
    }
    this.endpoint = undefined;
    this.bearerToken = undefined;
    this.studyInstanceUid = undefined;
  }

  private queue(action: 'upsert' | 'remove', measurement: any): void {
    const uid = String(measurement?.uid || '');
    if (!uid || !this.endpoint || !this.bearerToken || !this.studyInstanceUid) {
      return;
    }

    this.pending.set(uid, { action, measurement });
    const delay = Number((window as any).config?.voxelMeasurementAdapter?.debounceMs || 600);
    this.scheduleFlush(Number.isFinite(delay) ? delay : 600);
  }

  private async flush(): Promise<void> {
    this.flushTimer = undefined;
    const queue = [...this.pending.values()];
    this.pending.clear();

    let hasFailure = false;
    for (const item of queue) {
      try {
        await this.send(item.action, item.measurement);
      } catch (error) {
        // Falhas de rede não impedem a prática clínica no viewer. Mantemos um
        // snapshot em memória para nova tentativa, sem sobrepor update mais novo.
        const uid = String(item.measurement?.uid || '');
        if (uid && !this.pending.has(uid)) {
          this.pending.set(uid, item);
        }
        hasFailure = true;
        console.warn('[VOXEL Measurement Adapter] Falha de sincronização', error);
      }
    }

    if (hasFailure && this.pending.size) {
      this.scheduleFlush(5000);
    }
  }

  private scheduleFlush(delay: number): void {
    if (this.flushTimer) {
      window.clearTimeout(this.flushTimer);
    }
    this.flushTimer = window.setTimeout(() => this.flush(), delay);
  }

  private async send(action: 'upsert' | 'remove', measurement: any): Promise<void> {
    if (!this.endpoint || !this.bearerToken || !this.studyInstanceUid) {
      return;
    }

    const snapshot = action === 'remove'
      ? { uid: String(measurement?.uid || '') }
      : this.normalizeMeasurement(measurement);
    if (!snapshot.uid) {
      return;
    }

    const response = await fetch(this.endpoint, {
      method: 'POST',
      mode: 'cors',
      credentials: 'omit',
      cache: 'no-store',
      headers: {
        Authorization: `Bearer ${this.bearerToken}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        action,
        study_instance_uid: this.studyInstanceUid,
        measurement: snapshot,
      }),
    });

    if (!response.ok) {
      throw new Error(`Endpoint de medições respondeu HTTP ${response.status}`);
    }
  }

  private normalizeMeasurement(measurement: any): Record<string, any> {
    const toolName = String(measurement?.toolName || measurement?.metadata?.toolName || '');
    const stats = this.extractStats(measurement?.data);
    const displayValue = this.getDisplayValue(measurement, stats, toolName);
    const numericValue = this.getNumericValue(stats, toolName);
    const unit = this.getUnit(stats, toolName);

    return {
      uid: String(measurement?.uid || ''),
      tool_name: toolName,
      source_name: String(measurement?.source?.name || ''),
      source_version: String(measurement?.source?.version || ''),
      series_instance_uid: measurement?.referenceSeriesUID || measurement?.metadata?.SeriesInstanceUID || null,
      sop_instance_uid: measurement?.SOPInstanceUID || measurement?.metadata?.SOPInstanceUID || null,
      frame_of_reference_uid: measurement?.FrameOfReferenceUID || measurement?.metadata?.FrameOfReferenceUID || null,
      frame_number: measurement?.frameNumber || null,
      label: measurement?.label || null,
      display_value: displayValue,
      numeric_value: numericValue,
      unit,
      points: Array.isArray(measurement?.points) ? measurement.points : null,
      captured_at_client: new Date().toISOString(),
    };
  }

  private extractStats(data: any): Record<string, any> {
    if (!data || typeof data !== 'object') {
      return {};
    }

    const candidates = [data, data.cachedStats, data.stats].filter(Boolean);
    for (const candidate of candidates) {
      const found = this.findStats(candidate, 0);
      if (Object.keys(found).length) {
        return found;
      }
    }

    return {};
  }

  private findStats(value: any, depth: number): Record<string, any> {
    if (!value || typeof value !== 'object' || depth > 3) {
      return {};
    }

    const keys = ['length', 'area', 'perimeter', 'angle', 'mean', 'stdDev', 'shortestDiameter', 'longestDiameter', 'unit'];
    const found: Record<string, any> = {};
    keys.forEach(key => {
      if (value[key] !== undefined && value[key] !== null) {
        found[key] = value[key];
      }
    });
    if (Object.keys(found).length) {
      return found;
    }

    for (const nested of Object.values(value)) {
      const nestedFound = this.findStats(nested, depth + 1);
      if (Object.keys(nestedFound).length) {
        return nestedFound;
      }
    }

    return {};
  }

  private getDisplayValue(measurement: any, stats: Record<string, any>, toolName: string): string {
    const primary = measurement?.displayText?.primary;
    if (Array.isArray(primary) && primary[0]) {
      return String(primary[0]).slice(0, 255);
    }

    const value = this.getNumericValue(stats, toolName);
    const unit = this.getUnit(stats, toolName);
    if (value !== null) {
      return `${value}${unit ? ` ${unit}` : ''}`.slice(0, 255);
    }

    return toolName || 'Medição sem valor calculado';
  }

  private getNumericValue(stats: Record<string, any>, toolName: string): number | null {
    const orderedKeys = toolName === 'Angle' || toolName === 'CobbAngle'
      ? ['angle', 'length', 'area', 'mean']
      : ['length', 'area', 'perimeter', 'mean', 'shortestDiameter', 'longestDiameter', 'angle'];

    for (const key of orderedKeys) {
      const value = stats[key];
      if (typeof value === 'number' && Number.isFinite(value)) {
        return value;
      }
    }
    return null;
  }

  private getUnit(stats: Record<string, any>, toolName: string): string | null {
    if (typeof stats.unit === 'string' && stats.unit.length <= 32) {
      return stats.unit;
    }
    if (toolName === 'Angle' || toolName === 'CobbAngle') {
      return '°';
    }
    return null;
  }

  private getStudyInstanceUid(): string | undefined {
    const fromQuery = new URLSearchParams(window.location.search).get('StudyInstanceUIDs');
    return fromQuery ? fromQuery.split(',')[0] : undefined;
  }

  private consumeTokenFromFragment(): string | undefined {
    const hash = window.location.hash.startsWith('#') ? window.location.hash.slice(1) : '';
    const values = new URLSearchParams(hash);
    const token = values.get('voxel_measurement_token') || undefined;
    if (!token || !/^[a-f0-9]{64}$/i.test(token)) {
      return undefined;
    }

    values.delete('voxel_measurement_token');
    const remainingHash = values.toString();
    const cleanUrl = `${window.location.pathname}${window.location.search}${remainingHash ? `#${remainingHash}` : ''}`;
    window.history.replaceState({}, document.title, cleanUrl);
    return token;
  }
}
