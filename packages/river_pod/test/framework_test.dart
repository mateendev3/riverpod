import 'package:meta/meta.dart';
import 'package:mockito/mockito.dart';
import 'package:river_pod/src/internals.dart';
import 'package:test/test.dart';
import 'package:river_pod/river_pod.dart';

void main() {
  group('onError', () {
    // TODO error handling initState
    // TODO error handling didUpdateProvider
    // TODO error handling dispose
    // TODO error handling watchOwner callback
    // TODO error handling state.onDispose callback
    // TODO error handling state.onChange (if any) callback
    // TODO no onError fallback to zone
  });
  // TODO test dependOn disposes the provider state (keep alive?)
  test('dependOn', () {
    final provider = TestProvider((state) => 0);
    final provider2 = TestProvider((state) => 1);
    final owner = ProviderStateOwner();

    final value1 = owner.dependOn(provider);
    final value2 = owner.dependOn(provider);
    final value21 = owner.dependOn(provider2);
    final value22 = owner.dependOn(provider2);

    expect(value1, value2);
    expect(value1.value, 0);
    expect(value21, value22);
    expect(value21, isNot(value1));
    expect(value21.value, 1);

    verifyZeroInteractions(provider.onValueDispose);
    verifyZeroInteractions(provider2.onValueDispose);

    owner.dispose();

    verify(provider.onValueDispose(value1));
    verify(provider2.onValueDispose(value21));
  });
  test(
      "updating overrides / dispose don't compute provider states if not loaded yet",
      () {
    var callCount = 0;
    final provider = Provider((_) => callCount++);

    final owner = ProviderStateOwner(
      overrides: [provider.overrideForSubtree(provider)],
    );

    expect(callCount, 0);

    owner.updateOverrides(
      [provider.overrideForSubtree(provider)],
    );

    expect(callCount, 0);

    owner.dispose();

    expect(callCount, 0);
    expect(provider.readOwner(owner), 0);
    expect(callCount, 1);
  });
  test('circular dependencies', () {
    Provider<int Function()> provider;

    final provider1 = Provider((state) {
      return state.dependOn(provider).value() + 1;
    });
    final provider2 = Provider((state) {
      return state.dependOn(provider1).value + 1;
    });
    provider = Provider((state) {
      return () => state.dependOn(provider2).value + 1;
    });

    final owner = ProviderStateOwner();
    expect(
      () => provider.readOwner(owner)(),
      throwsA(isA<CircularDependencyError>()),
    );
  });
  test('circular dependencies #2', () {
    final owner = ProviderStateOwner();

    final provider = Provider((state) => state);
    final provider1 = Provider((state) => state);
    final provider2 = Provider((state) => state);

    provider1.readOwner(owner).dependOn(provider);
    provider2.readOwner(owner).dependOn(provider1);
    final providerState = provider.readOwner(owner);

    expect(
      () => providerState.dependOn(provider2),
      throwsA(isA<CircularDependencyError>()),
    );
  });
  test('dispose providers in dependency order (simple)', () {
    final owner = ProviderStateOwner();
    final onDispose1 = OnDisposeMock();
    final onDispose2 = OnDisposeMock();
    final onDispose3 = OnDisposeMock();

    final provider1 = Provider((state) {
      state.onDispose(onDispose1);
      return 1;
    });

    final provider2 = Provider((state) {
      final value = state.dependOn(provider1).value;
      state.onDispose(onDispose2);
      return value + 1;
    });

    final provider3 = Provider((state) {
      final value = state.dependOn(provider2).value;
      state.onDispose(onDispose3);
      return value + 1;
    });

    expect(provider3.readOwner(owner), 3);

    owner.dispose();

    verifyInOrder([
      onDispose1(),
      onDispose2(),
      onDispose3(),
    ]);
    verifyNoMoreInteractions(onDispose1);
    verifyNoMoreInteractions(onDispose2);
    verifyNoMoreInteractions(onDispose3);
  });

  test('dispose providers in dependency order (late binding)', () {
    final owner = ProviderStateOwner();
    final onDispose1 = OnDisposeMock();
    final onDispose2 = OnDisposeMock();
    final onDispose3 = OnDisposeMock();

    final provider1 = Provider((state) {
      state.onDispose(onDispose1);
      return 1;
    });

    final provider2 = Provider((state) {
      state.onDispose(onDispose2);
      return () => state.dependOn(provider1).value + 1;
    });

    final provider3 = Provider((state) {
      state.onDispose(onDispose3);
      return () => state.dependOn(provider2).value() + 1;
    });

    expect(provider3.readOwner(owner)(), 3);

    owner.dispose();

    verifyInOrder([
      onDispose1(),
      onDispose2(),
      onDispose3(),
    ]);
    verifyNoMoreInteractions(onDispose1);
    verifyNoMoreInteractions(onDispose2);
    verifyNoMoreInteractions(onDispose3);
  });
  test('update providers in dependency order', () {
    final provider = TestProvider((_) => 1);
    final provider1 = TestProvider((state) {
      return () => state.dependOn(provider).value + 1;
    });
    final provider2 = TestProvider((state) {
      return () => state.dependOn(provider1).value() + 1;
    });

    final owner = ProviderStateOwner(overrides: [
      provider.overrideForSubtree(provider),
      provider1.overrideForSubtree(provider1),
      provider2.overrideForSubtree(provider2),
    ]);

    expect(provider2.readOwner(owner)(), 3);

    verifyZeroInteractions(provider.onDidUpdateProvider);
    verifyZeroInteractions(provider1.onDidUpdateProvider);
    verifyZeroInteractions(provider2.onDidUpdateProvider);

    owner.updateOverrides([
      provider.overrideForSubtree(provider),
      provider1.overrideForSubtree(provider1),
      provider2.overrideForSubtree(provider2),
    ]);

    verifyInOrder([
      provider.onDidUpdateProvider(),
      provider1.onDidUpdateProvider(),
      provider2.onDidUpdateProvider(),
    ]);
    verifyNoMoreInteractions(provider.onDidUpdateProvider);
    verifyNoMoreInteractions(provider1.onDidUpdateProvider);
    verifyNoMoreInteractions(provider2.onDidUpdateProvider);

    owner.dispose();
  });
  test('dependOn used on same provider multiple times returns same instance',
      () {
    final owner = ProviderStateOwner();
    final provider = Provider((_) => 42);

    ProviderValue<int> other;
    ProviderValue<int> other2;

    final provider1 = Provider((state) {
      other = state.dependOn(provider);
      other2 = state.dependOn(provider);
      return other.value;
    });

    expect(provider1.readOwner(owner), 42);
    expect(other, other2);

    owner.dispose();
  });
  test('ProviderState is unusable after dispose (dependOn/onDispose)', () {
    final owner = ProviderStateOwner();
    ProviderState state;
    final provider = Provider((s) {
      state = s;
      return 42;
    });
    final other = Provider((_) => 42);

    expect(provider.readOwner(owner), 42);
    owner.dispose();

    expect(state.mounted, isFalse);
    expect(() => state.onDispose(() {}), throwsA(isA<AssertionError>()));
    expect(() => state.dependOn(other), throwsA(isA<AssertionError>()));
  });
}

class OnDisposeMock extends Mock {
  void call();
}

class MockDidUpdateProvider extends Mock {
  void call();
}

class MockOnValueDispose<T> extends Mock {
  void call(TestProviderValue<T> value);
}

class TestProviderValue<T> extends BaseProviderValue {
  TestProviderValue(this.value, {@required this.onDispose});

  final T value;
  final MockOnValueDispose<T> onDispose;

  @override
  void dispose() {
    onDispose(this);
    super.dispose();
  }
}

class TestProvider<T> extends AlwaysAliveProvider<TestProviderValue<T>, T> {
  TestProvider(this.create);

  final T Function(ProviderState state) create;
  final MockDidUpdateProvider onDidUpdateProvider = MockDidUpdateProvider();
  final MockOnValueDispose<T> onValueDispose = MockOnValueDispose();

  @override
  TestProviderState<T> createState() {
    return TestProviderState<T>();
  }
}

class TestProviderState<T>
    extends BaseProviderState<TestProviderValue<T>, T, TestProvider<T>> {
  @override
  void didUpdateProvider(TestProvider<T> oldProvider) {
    super.didUpdateProvider(oldProvider);
    provider.onDidUpdateProvider?.call();
  }

  @override
  TestProviderValue<T> createProviderValue() {
    return TestProviderValue<T>($state, onDispose: provider.onValueDispose);
  }

  @override
  T initState() {
    return provider.create(ProviderState(this));
  }
}
