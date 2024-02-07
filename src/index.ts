import { NativeModules, NativeEventEmitter } from 'react-native';

type EventSubscription = {
  remove: () => void;
};

interface Events {
  (
    eventName: 'change',
    handler: (event: { key: string; value: string | null }) => void
  ): EventSubscription;
  (
    eventName: 'delete',
    handler: (event: { key: string }) => void
  ): EventSubscription;
}

const { CloudKitStorage } = NativeModules;
const events = new NativeEventEmitter(CloudKitStorage);

export default {
  registerForPushUpdates: CloudKitStorage.registerForPushUpdates,
  getItem: (
    recordName: string,
    recordType?: string,
    field?: string
  ): Promise<string> => {
    return CloudKitStorage.getItem(recordName, recordType, field);
  },

  setItem: (
    recordName: string,
    contents: string,
    recordType?: string,
    field?: string
  ): Promise<void> => {
    return CloudKitStorage.setItem(recordName, contents, recordType, field);
  },
  addListener: ((event, handler) => {
    return events.addListener(event, handler);
  }) as Events,
};
