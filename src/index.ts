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
  getItem: CloudKitStorage.getItem,
  setItem: CloudKitStorage.setItem,
  addListener: ((event, handler) => {
    return events.addListener(event, handler);
  }) as Events,
};
