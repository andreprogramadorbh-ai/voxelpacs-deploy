import VoxelMeasurementAdapterService from './services/VoxelMeasurementAdapterService/VoxelMeasurementAdapterService';

const id = '@voxel/extension-measurement-adapter';

/**
 * Extensão VOXEL independente: observa o MeasurementService; não cria source,
 * não altera mappers e não modifica o estado nativo do OHIF.
 */
const voxelMeasurementAdapterExtension = {
  id,

  preRegistration({ servicesManager }) {
    servicesManager.registerService(VoxelMeasurementAdapterService.REGISTRATION);
  },

  onModeEnter({ servicesManager, extensionManager }) {
    servicesManager.services.voxelMeasurementAdapterService?.onModeEnter({
      servicesManager,
      extensionManager,
    });
  },

  onModeExit({ servicesManager }) {
    servicesManager.services.voxelMeasurementAdapterService?.onModeExit();
  },
};

export default voxelMeasurementAdapterExtension;
export { id, VoxelMeasurementAdapterService };
